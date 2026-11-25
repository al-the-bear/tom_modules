#include "tom_media_extract_probe_plugin.h"

// This must be included before many other Windows headers.
#include <windows.h>

#include <mfapi.h>
#include <mferror.h>
#include <mfidl.h>
#include <mfreadwrite.h>
#include <propvarutil.h>
#include <shlwapi.h>
#include <wincodec.h>
#include <wrl/client.h>

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <cmath>
#include <cstdio>
#include <functional>
#include <memory>
#include <sstream>
#include <string>
#include <vector>

// Audio and still frames out of a video with Media Foundation's Source
// Reader, which finds the demuxer and the decoders Windows has. The decoder
// gives the track's own sample rate and channel count, so the conversion to
// the ones asked for is done here. Frames are written as JPEG by the Windows
// Imaging Component.
//
// The calls run on the platform thread and block it while they work; a
// library runs them on a thread of its own.

namespace tom_media_extract_probe {

namespace {

using flutter::EncodableMap;
using flutter::EncodableValue;
using Microsoft::WRL::ComPtr;

std::wstring Wide(const std::string& text) {
  if (text.empty()) {
    return std::wstring();
  }
  int size = MultiByteToWideChar(CP_UTF8, 0, text.data(),
                                 static_cast<int>(text.size()), nullptr, 0);
  std::wstring wide(size, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, text.data(), static_cast<int>(text.size()),
                      wide.data(), size);
  return wide;
}

std::string Problem(const char* what, HRESULT hr) {
  std::ostringstream text;
  text << what << " (0x" << std::hex << static_cast<unsigned long>(hr) << ")";
  if (hr == MF_E_UNSUPPORTED_BYTESTREAM_TYPE) {
    text << ": Windows has no reader for this container";
  } else if (hr == MF_E_TOPO_CODEC_NOT_FOUND ||
             hr == MF_E_INVALIDMEDIATYPE) {
    text << ": Windows has no decoder for this codec";
  }
  return text.str();
}

HRESULT OpenReader(const std::string& path, bool video_processing,
                   ComPtr<IMFSourceReader>& reader) {
  ComPtr<IMFAttributes> attributes;
  HRESULT hr = MFCreateAttributes(&attributes, 1);
  if (FAILED(hr)) {
    return hr;
  }
  if (video_processing) {
    attributes->SetUINT32(MF_SOURCE_READER_ENABLE_VIDEO_PROCESSING, TRUE);
  }
  return MFCreateSourceReaderFromURL(Wide(path).c_str(), attributes.Get(),
                                     &reader);
}

// The four characters of a subtype GUID's first field, or its number.
std::string SubtypeName(const GUID& subtype) {
  char characters[5] = {0};
  bool printable = true;
  for (int i = 0; i < 4; i++) {
    char c = static_cast<char>((subtype.Data1 >> (8 * i)) & 0xff);
    if (c < 32 || c > 126) {
      printable = false;
    }
    characters[i] = c;
  }
  if (printable) {
    return characters;
  }
  std::ostringstream text;
  text << "0x" << std::hex << subtype.Data1;
  return text.str();
}

// Mixes 16-bit interleaved samples to the channels asked for and resamples
// them by linear interpolation, keeping its place between blocks.
class Converter {
 public:
  Converter(int rate, int channels) : rate_(rate), channels_(channels) {}

  void Convert(const int16_t* source, size_t frames, int source_rate,
               int source_channels, std::vector<uint8_t>& out) {
    if (frames == 0) {
      return;
    }
    std::vector<float> mixed(frames * channels_);
    for (size_t f = 0; f < frames; f++) {
      if (channels_ == 1) {
        float sum = 0;
        for (int c = 0; c < source_channels; c++) {
          sum += source[f * source_channels + c];
        }
        mixed[f] = sum / source_channels;
      } else {
        for (int c = 0; c < channels_; c++) {
          mixed[f * channels_ + c] =
              source[f * source_channels + (c % source_channels)];
        }
      }
    }
    auto put = [&out](float value) {
      int sample = static_cast<int>(value);
      if (sample > 32767) sample = 32767;
      if (sample < -32768) sample = -32768;
      out.push_back(static_cast<uint8_t>(sample & 0xff));
      out.push_back(static_cast<uint8_t>((sample >> 8) & 0xff));
    };
    if (source_rate == rate_) {
      for (float value : mixed) {
        put(value);
      }
      return;
    }
    double step = static_cast<double>(source_rate) / rate_;
    if (last_.empty()) {
      position_ = 0;
    }
    // Frame -1 is the last frame of the block before.
    while (position_ < static_cast<double>(frames) - 1) {
      long index = static_cast<long>(std::floor(position_));
      float fraction = static_cast<float>(position_ - index);
      for (int c = 0; c < channels_; c++) {
        float a = index < 0 ? last_[c] : mixed[index * channels_ + c];
        float b = mixed[(index + 1) * channels_ + c];
        put(a + (b - a) * fraction);
      }
      position_ += step;
    }
    last_.assign(mixed.end() - channels_, mixed.end());
    position_ -= static_cast<double>(frames);
  }

 private:
  int rate_;
  int channels_;
  double position_ = 0;
  std::vector<float> last_;
};

std::string Info(const std::string& path, EncodableMap& out) {
  ComPtr<IMFSourceReader> reader;
  HRESULT hr = OpenReader(path, false, reader);
  if (FAILED(hr)) {
    return Problem("Media Foundation cannot open the file", hr);
  }
  PROPVARIANT duration;
  PropVariantInit(&duration);
  if (SUCCEEDED(reader->GetPresentationAttribute(
          static_cast<DWORD>(MF_SOURCE_READER_MEDIASOURCE), MF_PD_DURATION,
          &duration))) {
    out[EncodableValue("durationMs")] =
        EncodableValue(static_cast<int64_t>(duration.uhVal.QuadPart / 10000));
  }
  PropVariantClear(&duration);
  ComPtr<IMFMediaType> video;
  bool has_video = SUCCEEDED(reader->GetNativeMediaType(
      static_cast<DWORD>(MF_SOURCE_READER_FIRST_VIDEO_STREAM), 0, &video));
  out[EncodableValue("hasVideo")] = EncodableValue(has_video);
  if (has_video) {
    UINT32 width = 0;
    UINT32 height = 0;
    MFGetAttributeSize(video.Get(), MF_MT_FRAME_SIZE, &width, &height);
    out[EncodableValue("width")] = EncodableValue(static_cast<int>(width));
    out[EncodableValue("height")] = EncodableValue(static_cast<int>(height));
    GUID subtype;
    if (SUCCEEDED(video->GetGUID(MF_MT_SUBTYPE, &subtype))) {
      out[EncodableValue("videoCodec")] = EncodableValue(SubtypeName(subtype));
    }
  }
  ComPtr<IMFMediaType> audio;
  bool has_audio = SUCCEEDED(reader->GetNativeMediaType(
      static_cast<DWORD>(MF_SOURCE_READER_FIRST_AUDIO_STREAM), 0, &audio));
  out[EncodableValue("hasAudio")] = EncodableValue(has_audio);
  if (has_audio) {
    out[EncodableValue("sampleRate")] = EncodableValue(static_cast<int>(
        MFGetAttributeUINT32(audio.Get(), MF_MT_AUDIO_SAMPLES_PER_SECOND, 0)));
    out[EncodableValue("channels")] = EncodableValue(static_cast<int>(
        MFGetAttributeUINT32(audio.Get(), MF_MT_AUDIO_NUM_CHANNELS, 0)));
    GUID subtype;
    if (SUCCEEDED(audio->GetGUID(MF_MT_SUBTYPE, &subtype))) {
      out[EncodableValue("audioCodec")] = EncodableValue(SubtypeName(subtype));
    }
  }
  if (!has_video && !has_audio) {
    return "Media Foundation finds no audio or video stream";
  }
  return std::string();
}

// Decodes the sound and hands every converted block to `sink`. Answers an
// empty string, or what went wrong.
std::string DecodeAudio(
    const std::string& path, int rate, int channels, int64_t start_ms,
    int64_t duration_ms,
    const std::function<void(const std::vector<uint8_t>&)>& sink) {
  ComPtr<IMFSourceReader> reader;
  HRESULT hr = OpenReader(path, false, reader);
  if (FAILED(hr)) {
    return Problem("Media Foundation cannot open the file", hr);
  }
  const DWORD stream = static_cast<DWORD>(MF_SOURCE_READER_FIRST_AUDIO_STREAM);
  reader->SetStreamSelection(static_cast<DWORD>(MF_SOURCE_READER_ALL_STREAMS),
                             FALSE);
  hr = reader->SetStreamSelection(stream, TRUE);
  if (FAILED(hr)) {
    return Problem("the file has no audio stream", hr);
  }
  ComPtr<IMFMediaType> pcm;
  MFCreateMediaType(&pcm);
  pcm->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Audio);
  pcm->SetGUID(MF_MT_SUBTYPE, MFAudioFormat_PCM);
  pcm->SetUINT32(MF_MT_AUDIO_BITS_PER_SAMPLE, 16);
  hr = reader->SetCurrentMediaType(stream, nullptr, pcm.Get());
  if (FAILED(hr)) {
    return Problem("the audio cannot be decoded", hr);
  }
  ComPtr<IMFMediaType> current;
  reader->GetCurrentMediaType(stream, &current);
  int source_rate = static_cast<int>(
      MFGetAttributeUINT32(current.Get(), MF_MT_AUDIO_SAMPLES_PER_SECOND, 0));
  int source_channels = static_cast<int>(
      MFGetAttributeUINT32(current.Get(), MF_MT_AUDIO_NUM_CHANNELS, 0));
  const LONGLONG start = start_ms * 10000;
  const LONGLONG end =
      duration_ms >= 0 ? (start_ms + duration_ms) * 10000 : MAXLONGLONG;
  if (start > 0) {
    PROPVARIANT position;
    InitPropVariantFromInt64(start, &position);
    reader->SetCurrentPosition(GUID_NULL, position);
    PropVariantClear(&position);
  }
  Converter converter(rate, channels);
  std::vector<uint8_t> block;
  while (true) {
    DWORD flags = 0;
    LONGLONG time = 0;
    ComPtr<IMFSample> sample;
    hr = reader->ReadSample(stream, 0, nullptr, &flags, &time, &sample);
    if (FAILED(hr)) {
      return Problem("reading the audio failed", hr);
    }
    if (flags & MF_SOURCE_READERF_CURRENTMEDIATYPECHANGED) {
      current.Reset();
      reader->GetCurrentMediaType(stream, &current);
      source_rate = static_cast<int>(MFGetAttributeUINT32(
          current.Get(), MF_MT_AUDIO_SAMPLES_PER_SECOND, source_rate));
      source_channels = static_cast<int>(MFGetAttributeUINT32(
          current.Get(), MF_MT_AUDIO_NUM_CHANNELS, source_channels));
    }
    if (flags & MF_SOURCE_READERF_ENDOFSTREAM) {
      break;
    }
    if (!sample || source_rate == 0 || source_channels == 0) {
      continue;
    }
    if (time >= end) {
      break;
    }
    if (time < start) {
      continue;
    }
    ComPtr<IMFMediaBuffer> buffer;
    if (FAILED(sample->ConvertToContiguousBuffer(&buffer))) {
      continue;
    }
    BYTE* data = nullptr;
    DWORD length = 0;
    if (FAILED(buffer->Lock(&data, nullptr, &length))) {
      continue;
    }
    block.clear();
    converter.Convert(reinterpret_cast<const int16_t*>(data),
                      length / (2 * source_channels), source_rate,
                      source_channels, block);
    buffer->Unlock();
    sink(block);
  }
  return std::string();
}

void PutWavHeader(FILE* file, uint32_t data_bytes, int rate, int channels) {
  uint8_t header[44];
  auto put32 = [&header](int at, uint32_t value) {
    for (int i = 0; i < 4; i++) {
      header[at + i] = static_cast<uint8_t>((value >> (8 * i)) & 0xff);
    }
  };
  auto put16 = [&header](int at, uint32_t value) {
    header[at] = static_cast<uint8_t>(value & 0xff);
    header[at + 1] = static_cast<uint8_t>((value >> 8) & 0xff);
  };
  memcpy(header, "RIFF", 4);
  put32(4, 36 + data_bytes);
  memcpy(header + 8, "WAVEfmt ", 8);
  put32(16, 16);
  put16(20, 1);
  put16(22, channels);
  put32(24, rate);
  put32(28, rate * channels * 2);
  put16(32, channels * 2);
  put16(34, 16);
  memcpy(header + 36, "data", 4);
  put32(40, data_bytes);
  fseek(file, 0, SEEK_SET);
  fwrite(header, 1, sizeof(header), file);
}

// Writes BGRA pixels as a JPEG, scaled to `max_width` when that is smaller.
std::string EncodeJpeg(const uint8_t* pixels, UINT width, UINT height,
                       UINT stride, UINT max_width, std::vector<uint8_t>& jpeg,
                       UINT& out_width, UINT& out_height) {
  ComPtr<IWICImagingFactory> factory;
  HRESULT hr = CoCreateInstance(CLSID_WICImagingFactory, nullptr,
                                CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&factory));
  if (FAILED(hr)) {
    return Problem("no imaging factory", hr);
  }
  ComPtr<IWICBitmap> bitmap;
  hr = factory->CreateBitmapFromMemory(
      width, height, GUID_WICPixelFormat32bppBGR, stride, stride * height,
      const_cast<BYTE*>(pixels), &bitmap);
  if (FAILED(hr)) {
    return Problem("the frame cannot be wrapped", hr);
  }
  ComPtr<IWICBitmapSource> source = bitmap;
  out_width = width;
  out_height = height;
  if (max_width > 0 && max_width < width) {
    out_width = max_width;
    out_height = height * max_width / width;
    ComPtr<IWICBitmapScaler> scaler;
    hr = factory->CreateBitmapScaler(&scaler);
    if (SUCCEEDED(hr)) {
      hr = scaler->Initialize(bitmap.Get(), out_width, out_height,
                              WICBitmapInterpolationModeFant);
    }
    if (FAILED(hr)) {
      return Problem("the frame cannot be scaled", hr);
    }
    source = scaler;
  }
  ComPtr<IWICFormatConverter> converted;
  hr = factory->CreateFormatConverter(&converted);
  if (SUCCEEDED(hr)) {
    hr = converted->Initialize(source.Get(), GUID_WICPixelFormat24bppBGR,
                               WICBitmapDitherTypeNone, nullptr, 0.0,
                               WICBitmapPaletteTypeCustom);
  }
  if (FAILED(hr)) {
    return Problem("the frame cannot be converted", hr);
  }
  ComPtr<IStream> stream;
  hr = CreateStreamOnHGlobal(nullptr, TRUE, &stream);
  ComPtr<IWICBitmapEncoder> encoder;
  if (SUCCEEDED(hr)) {
    hr = factory->CreateEncoder(GUID_ContainerFormatJpeg, nullptr, &encoder);
  }
  if (SUCCEEDED(hr)) {
    hr = encoder->Initialize(stream.Get(), WICBitmapEncoderNoCache);
  }
  ComPtr<IWICBitmapFrameEncode> frame;
  ComPtr<IPropertyBag2> options;
  if (SUCCEEDED(hr)) {
    hr = encoder->CreateNewFrame(&frame, &options);
  }
  if (SUCCEEDED(hr)) {
    PROPBAG2 option = {0};
    option.pstrName = const_cast<LPOLESTR>(L"ImageQuality");
    VARIANT value;
    VariantInit(&value);
    value.vt = VT_R4;
    value.fltVal = 0.8f;
    options->Write(1, &option, &value);
    hr = frame->Initialize(options.Get());
  }
  if (SUCCEEDED(hr)) {
    hr = frame->SetSize(out_width, out_height);
  }
  if (SUCCEEDED(hr)) {
    WICPixelFormatGUID format = GUID_WICPixelFormat24bppBGR;
    hr = frame->SetPixelFormat(&format);
  }
  if (SUCCEEDED(hr)) {
    hr = frame->WriteSource(converted.Get(), nullptr);
  }
  if (SUCCEEDED(hr)) {
    hr = frame->Commit();
  }
  if (SUCCEEDED(hr)) {
    hr = encoder->Commit();
  }
  if (FAILED(hr)) {
    return Problem("the JPEG could not be written", hr);
  }
  STATSTG stat = {0};
  stream->Stat(&stat, STATFLAG_NONAME);
  jpeg.resize(static_cast<size_t>(stat.cbSize.QuadPart));
  LARGE_INTEGER zero = {0};
  stream->Seek(zero, STREAM_SEEK_SET, nullptr);
  ULONG read = 0;
  stream->Read(jpeg.data(), static_cast<ULONG>(jpeg.size()), &read);
  return std::string();
}

std::string Frame(const std::string& path, int64_t time_ms, int max_width,
                  bool exact, EncodableMap& out) {
  ComPtr<IMFSourceReader> reader;
  HRESULT hr = OpenReader(path, true, reader);
  if (FAILED(hr)) {
    return Problem("Media Foundation cannot open the file", hr);
  }
  const DWORD stream = static_cast<DWORD>(MF_SOURCE_READER_FIRST_VIDEO_STREAM);
  reader->SetStreamSelection(static_cast<DWORD>(MF_SOURCE_READER_ALL_STREAMS),
                             FALSE);
  hr = reader->SetStreamSelection(stream, TRUE);
  if (FAILED(hr)) {
    return Problem("the file has no video stream", hr);
  }
  ComPtr<IMFMediaType> rgb;
  MFCreateMediaType(&rgb);
  rgb->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video);
  rgb->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_RGB32);
  hr = reader->SetCurrentMediaType(stream, nullptr, rgb.Get());
  if (FAILED(hr)) {
    return Problem("the video cannot be decoded", hr);
  }
  const LONGLONG target = time_ms * 10000;
  PROPVARIANT position;
  InitPropVariantFromInt64(target, &position);
  hr = reader->SetCurrentPosition(GUID_NULL, position);
  PropVariantClear(&position);
  if (FAILED(hr)) {
    return Problem("the video cannot be positioned", hr);
  }
  // After a seek the reader starts at the key frame before the position.
  // That frame is the answer when the nearest key frame is enough; for the
  // exact frame the frames up to the position are decoded and dropped.
  ComPtr<IMFSample> chosen;
  LONGLONG chosen_time = 0;
  while (true) {
    DWORD flags = 0;
    LONGLONG time = 0;
    ComPtr<IMFSample> sample;
    hr = reader->ReadSample(stream, 0, nullptr, &flags, &time, &sample);
    if (FAILED(hr)) {
      return Problem("reading the video failed", hr);
    }
    if (sample) {
      chosen = sample;
      chosen_time = time;
      LONGLONG length = 0;
      sample->GetSampleDuration(&length);
      if (!exact || time + length > target) {
        break;
      }
    }
    if (flags & MF_SOURCE_READERF_ENDOFSTREAM) {
      break;
    }
  }
  if (!chosen) {
    return "no frame at that time";
  }
  ComPtr<IMFMediaType> current;
  reader->GetCurrentMediaType(stream, &current);
  UINT32 width = 0;
  UINT32 height = 0;
  MFGetAttributeSize(current.Get(), MF_MT_FRAME_SIZE, &width, &height);
  LONG stride = static_cast<LONG>(MFGetAttributeUINT32(
      current.Get(), MF_MT_DEFAULT_STRIDE, width * 4));
  ComPtr<IMFMediaBuffer> buffer;
  hr = chosen->ConvertToContiguousBuffer(&buffer);
  if (FAILED(hr)) {
    return Problem("the frame has no buffer", hr);
  }
  BYTE* data = nullptr;
  DWORD length = 0;
  hr = buffer->Lock(&data, nullptr, &length);
  if (FAILED(hr)) {
    return Problem("the frame cannot be read", hr);
  }
  const UINT row = width * 4;
  std::vector<uint8_t> pixels(static_cast<size_t>(row) * height);
  const UINT source_row = static_cast<UINT>(stride < 0 ? -stride : stride);
  for (UINT y = 0; y < height; y++) {
    // A negative stride means the rows are stored bottom up.
    const UINT from = stride < 0 ? height - 1 - y : y;
    if (static_cast<size_t>(from) * source_row + row <= length) {
      memcpy(pixels.data() + static_cast<size_t>(y) * row,
             data + static_cast<size_t>(from) * source_row, row);
    }
  }
  buffer->Unlock();
  std::vector<uint8_t> jpeg;
  UINT out_width = 0;
  UINT out_height = 0;
  std::string problem =
      EncodeJpeg(pixels.data(), width, height, row,
                 max_width > 0 ? static_cast<UINT>(max_width) : 0, jpeg,
                 out_width, out_height);
  if (!problem.empty()) {
    return problem;
  }
  out[EncodableValue("jpeg")] = EncodableValue(jpeg);
  out[EncodableValue("timeMs")] =
      EncodableValue(static_cast<int64_t>((chosen_time + 5000) / 10000));
  out[EncodableValue("width")] = EncodableValue(static_cast<int>(out_width));
  out[EncodableValue("height")] = EncodableValue(static_cast<int>(out_height));
  return std::string();
}

int64_t IntArg(const EncodableMap& args, const char* name, int64_t fallback) {
  auto found = args.find(EncodableValue(name));
  if (found == args.end()) {
    return fallback;
  }
  if (std::holds_alternative<int32_t>(found->second)) {
    return std::get<int32_t>(found->second);
  }
  if (std::holds_alternative<int64_t>(found->second)) {
    return std::get<int64_t>(found->second);
  }
  return fallback;
}

std::string StringArg(const EncodableMap& args, const char* name) {
  auto found = args.find(EncodableValue(name));
  if (found == args.end() ||
      !std::holds_alternative<std::string>(found->second)) {
    return std::string();
  }
  return std::get<std::string>(found->second);
}

}  // namespace

// static
void TomMediaExtractProbePlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), "tom_media_probe/extract",
          &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<TomMediaExtractProbePlugin>();

  channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto& call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });

  registrar->AddPlugin(std::move(plugin));
}

TomMediaExtractProbePlugin::TomMediaExtractProbePlugin() {
  MFStartup(MF_VERSION);
}

TomMediaExtractProbePlugin::~TomMediaExtractProbePlugin() { MFShutdown(); }

void TomMediaExtractProbePlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const auto* args = std::get_if<EncodableMap>(method_call.arguments());
  std::string path = args != nullptr ? StringArg(*args, "path") : "";
  if (path.empty()) {
    result->Error("arguments", "path is missing");
    return;
  }
  const std::string& method = method_call.method_name();
  int rate = static_cast<int>(IntArg(*args, "sampleRate", 16000));
  int channels = static_cast<int>(IntArg(*args, "channels", 1));
  std::string problem;
  if (method == "info") {
    EncodableMap out;
    problem = Info(path, out);
    if (problem.empty()) {
      result->Success(EncodableValue(out));
      return;
    }
  } else if (method == "audioToWav") {
    std::string out_path = StringArg(*args, "out");
    FILE* file = nullptr;
    _wfopen_s(&file, Wide(out_path).c_str(), L"wb");
    if (file == nullptr) {
      result->Error("extract", "cannot write " + out_path);
      return;
    }
    PutWavHeader(file, 0, rate, channels);
    uint64_t bytes = 0;
    problem = DecodeAudio(path, rate, channels, 0, -1,
                          [&](const std::vector<uint8_t>& block) {
                            fwrite(block.data(), 1, block.size(), file);
                            bytes += block.size();
                          });
    PutWavHeader(file, static_cast<uint32_t>(bytes), rate, channels);
    fclose(file);
    if (problem.empty()) {
      EncodableMap out;
      out[EncodableValue("frames")] =
          EncodableValue(static_cast<int64_t>(bytes / (2 * channels)));
      out[EncodableValue("sampleRate")] = EncodableValue(rate);
      out[EncodableValue("channels")] = EncodableValue(channels);
      result->Success(EncodableValue(out));
      return;
    }
  } else if (method == "audioPcm") {
    std::vector<uint8_t> samples;
    problem = DecodeAudio(path, rate, channels, IntArg(*args, "startMs", 0),
                          IntArg(*args, "durationMs", -1),
                          [&](const std::vector<uint8_t>& block) {
                            samples.insert(samples.end(), block.begin(),
                                           block.end());
                          });
    if (problem.empty()) {
      result->Success(EncodableValue(samples));
      return;
    }
  } else if (method == "frame") {
    bool exact = true;
    auto found = args->find(EncodableValue("exact"));
    if (found != args->end() && std::holds_alternative<bool>(found->second)) {
      exact = std::get<bool>(found->second);
    }
    EncodableMap out;
    problem = Frame(path, IntArg(*args, "timeMs", 0),
                    static_cast<int>(IntArg(*args, "maxWidth", 0)), exact, out);
    if (problem.empty()) {
      result->Success(EncodableValue(out));
      return;
    }
  } else {
    result->NotImplemented();
    return;
  }
  result->Error("extract", problem);
}

}  // namespace tom_media_extract_probe
