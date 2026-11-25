#include "include/tom_media_extract_probe/tom_media_extract_probe_plugin.h"

#include <flutter_linux/flutter_linux.h>
#include <gst/app/gstappsink.h>
#include <gst/gst.h>
#include <gst/pbutils/pbutils.h>
#include <gtk/gtk.h>

#include <cstdio>
#include <cstring>
#include <string>
#include <vector>

// Audio and still frames out of a video with the system's GStreamer, loaded
// at run time (LGPL, installed, never bundled): `uridecodebin` finds the
// demuxer and decoders among the plugins the machine has, an `appsink` hands
// the result over. What opens is what those plugins cover.
//
// The calls run on the platform thread and block it while they work; a
// library runs them on a thread of its own.

#define TOM_MEDIA_EXTRACT_PROBE_PLUGIN(obj)                                   \
  (G_TYPE_CHECK_INSTANCE_CAST((obj),                                          \
                              tom_media_extract_probe_plugin_get_type(),      \
                              TomMediaExtractProbePlugin))

struct _TomMediaExtractProbePlugin {
  GObject parent_instance;
};

G_DEFINE_TYPE(TomMediaExtractProbePlugin, tom_media_extract_probe_plugin,
              g_object_get_type())

namespace {

const GstClockTime kWait = 30 * GST_SECOND;

std::string ToUri(const gchar* path) {
  if (g_str_has_prefix(path, "file:")) {
    return path;
  }
  g_autofree gchar* uri = gst_filename_to_uri(path, nullptr);
  return uri != nullptr ? uri : "";
}

// The first error on the pipeline's bus, or `fallback`.
std::string BusError(GstElement* pipeline, const char* fallback) {
  g_autoptr(GstBus) bus = gst_element_get_bus(pipeline);
  g_autoptr(GstMessage) message =
      gst_bus_pop_filtered(bus, GST_MESSAGE_ERROR);
  if (message == nullptr) {
    return fallback;
  }
  g_autoptr(GError) error = nullptr;
  g_autofree gchar* debug = nullptr;
  gst_message_parse_error(message, &error, &debug);
  return error != nullptr ? error->message : fallback;
}

// Waits until the pipeline has reached the state it was sent to.
bool Settle(GstElement* pipeline) {
  return gst_element_get_state(pipeline, nullptr, nullptr, kWait) !=
         GST_STATE_CHANGE_FAILURE;
}

FlMethodResponse* Fail(const std::string& message) {
  return FL_METHOD_RESPONSE(
      fl_method_error_response_new("extract", message.c_str(), nullptr));
}

FlMethodResponse* Info(const std::string& uri) {
  g_autoptr(GError) error = nullptr;
  g_autoptr(GstDiscoverer) discoverer =
      gst_discoverer_new(kWait, &error);
  if (discoverer == nullptr) {
    return Fail(error->message);
  }
  g_autoptr(GstDiscovererInfo) info =
      gst_discoverer_discover_uri(discoverer, uri.c_str(), &error);
  if (info == nullptr) {
    return Fail(error != nullptr ? error->message : "GStreamer reads no stream");
  }
  g_autoptr(FlValue) out = fl_value_new_map();
  GstDiscovererResult result = gst_discoverer_info_get_result(info);
  if (result == GST_DISCOVERER_MISSING_PLUGINS) {
    std::string missing;
    const gchar** details =
        gst_discoverer_info_get_missing_elements_installer_details(info);
    for (int i = 0; details != nullptr && details[i] != nullptr; i++) {
      missing += details[i];
      missing += "; ";
    }
    fl_value_set_string_take(out, "missingPlugins",
                             fl_value_new_string(missing.c_str()));
  } else if (result != GST_DISCOVERER_OK && error != nullptr) {
    return Fail(error->message);
  }
  fl_value_set_string_take(
      out, "durationMs",
      fl_value_new_int(gst_discoverer_info_get_duration(info) / GST_MSECOND));
  GList* videos = gst_discoverer_info_get_video_streams(info);
  GList* audios = gst_discoverer_info_get_audio_streams(info);
  fl_value_set_string_take(out, "hasVideo",
                           fl_value_new_bool(videos != nullptr));
  fl_value_set_string_take(out, "hasAudio",
                           fl_value_new_bool(audios != nullptr));
  if (videos != nullptr) {
    GstDiscovererVideoInfo* video = GST_DISCOVERER_VIDEO_INFO(videos->data);
    fl_value_set_string_take(
        out, "width",
        fl_value_new_int(gst_discoverer_video_info_get_width(video)));
    fl_value_set_string_take(
        out, "height",
        fl_value_new_int(gst_discoverer_video_info_get_height(video)));
    g_autoptr(GstCaps) caps = gst_discoverer_stream_info_get_caps(
        GST_DISCOVERER_STREAM_INFO(video));
    if (caps != nullptr && gst_caps_get_size(caps) > 0) {
      fl_value_set_string_take(
          out, "videoCodec",
          fl_value_new_string(
              gst_structure_get_name(gst_caps_get_structure(caps, 0))));
    }
  }
  if (audios != nullptr) {
    GstDiscovererAudioInfo* audio = GST_DISCOVERER_AUDIO_INFO(audios->data);
    fl_value_set_string_take(
        out, "sampleRate",
        fl_value_new_int(gst_discoverer_audio_info_get_sample_rate(audio)));
    fl_value_set_string_take(
        out, "channels",
        fl_value_new_int(gst_discoverer_audio_info_get_channels(audio)));
    g_autoptr(GstCaps) caps = gst_discoverer_stream_info_get_caps(
        GST_DISCOVERER_STREAM_INFO(audio));
    if (caps != nullptr && gst_caps_get_size(caps) > 0) {
      fl_value_set_string_take(
          out, "audioCodec",
          fl_value_new_string(
              gst_structure_get_name(gst_caps_get_structure(caps, 0))));
    }
  }
  gst_discoverer_stream_info_list_free(videos);
  gst_discoverer_stream_info_list_free(audios);
  return FL_METHOD_RESPONSE(fl_method_success_response_new(out));
}

// Decodes the sound to 16-bit interleaved samples and hands every block to
// `sink`. Answers an empty string, or what went wrong.
template <typename Sink>
std::string DecodeAudio(const std::string& uri, int rate, int channels,
                        gint64 start_ms, gint64 duration_ms, Sink sink) {
  g_autofree gchar* description = g_strdup_printf(
      "uridecodebin uri=\"%s\" expose-all-streams=false caps=\"audio/x-raw\" "
      "! audioconvert ! audioresample "
      "! audio/x-raw,format=S16LE,layout=interleaved,rate=%d,channels=%d "
      "! appsink name=sink sync=false",
      uri.c_str(), rate, channels);
  g_autoptr(GError) error = nullptr;
  g_autoptr(GstElement) pipeline = gst_parse_launch(description, &error);
  if (pipeline == nullptr) {
    return error != nullptr ? error->message : "the pipeline cannot be built";
  }
  g_autoptr(GstElement) element =
      gst_bin_get_by_name(GST_BIN(pipeline), "sink");
  GstAppSink* app_sink = GST_APP_SINK(element);
  std::string problem;
  gst_element_set_state(pipeline, GST_STATE_PAUSED);
  if (!Settle(pipeline)) {
    problem = BusError(pipeline, "GStreamer cannot decode the audio");
  } else {
    if (start_ms > 0 || duration_ms >= 0) {
      gst_element_seek(
          pipeline, 1.0, GST_FORMAT_TIME,
          static_cast<GstSeekFlags>(GST_SEEK_FLAG_FLUSH |
                                    GST_SEEK_FLAG_ACCURATE),
          GST_SEEK_TYPE_SET, start_ms * GST_MSECOND,
          duration_ms >= 0 ? GST_SEEK_TYPE_SET : GST_SEEK_TYPE_NONE,
          duration_ms >= 0 ? (start_ms + duration_ms) * GST_MSECOND : 0);
      Settle(pipeline);
    }
    gst_element_set_state(pipeline, GST_STATE_PLAYING);
    while (true) {
      g_autoptr(GstSample) sample = gst_app_sink_pull_sample(app_sink);
      if (sample == nullptr) {
        break;
      }
      GstBuffer* buffer = gst_sample_get_buffer(sample);
      GstMapInfo map;
      if (gst_buffer_map(buffer, &map, GST_MAP_READ)) {
        sink(map.data, map.size);
        gst_buffer_unmap(buffer, &map);
      }
    }
    problem = BusError(pipeline, "");
  }
  gst_element_set_state(pipeline, GST_STATE_NULL);
  return problem;
}

void PutWavHeader(FILE* file, guint32 data_bytes, int rate, int channels) {
  guint8 header[44];
  auto put32 = [&header](int at, guint32 value) {
    header[at] = value & 0xff;
    header[at + 1] = (value >> 8) & 0xff;
    header[at + 2] = (value >> 16) & 0xff;
    header[at + 3] = (value >> 24) & 0xff;
  };
  auto put16 = [&header](int at, guint16 value) {
    header[at] = value & 0xff;
    header[at + 1] = (value >> 8) & 0xff;
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

FlMethodResponse* AudioToWav(const std::string& uri, const gchar* out,
                             int rate, int channels) {
  FILE* file = fopen(out, "wb");
  if (file == nullptr) {
    return Fail(std::string("cannot write ") + out);
  }
  PutWavHeader(file, 0, rate, channels);
  guint64 bytes = 0;
  std::string problem = DecodeAudio(
      uri, rate, channels, 0, -1, [&](const guint8* data, gsize size) {
        fwrite(data, 1, size, file);
        bytes += size;
      });
  PutWavHeader(file, static_cast<guint32>(bytes), rate, channels);
  fclose(file);
  if (!problem.empty()) {
    return Fail(problem);
  }
  g_autoptr(FlValue) answer = fl_value_new_map();
  fl_value_set_string_take(answer, "frames",
                           fl_value_new_int(bytes / (2 * channels)));
  fl_value_set_string_take(answer, "sampleRate", fl_value_new_int(rate));
  fl_value_set_string_take(answer, "channels", fl_value_new_int(channels));
  return FL_METHOD_RESPONSE(fl_method_success_response_new(answer));
}

FlMethodResponse* AudioPcm(const std::string& uri, int rate, int channels,
                           gint64 start_ms, gint64 duration_ms) {
  std::vector<guint8> samples;
  std::string problem = DecodeAudio(
      uri, rate, channels, start_ms, duration_ms,
      [&](const guint8* data, gsize size) {
        samples.insert(samples.end(), data, data + size);
      });
  if (!problem.empty()) {
    return Fail(problem);
  }
  g_autoptr(FlValue) answer =
      fl_value_new_uint8_list(samples.data(), samples.size());
  return FL_METHOD_RESPONSE(fl_method_success_response_new(answer));
}

FlMethodResponse* Frame(const std::string& uri, gint64 time_ms, int max_width,
                        bool exact) {
  // uridecodebin is left to expose every stream: told to stop at
  // `video/x-raw` (as the audio pipeline is told for `audio/x-raw`) it finds
  // no decoder for H.264 or H.265. The sound's pad stays unlinked.
  //
  // With the pixel aspect ratio fixed, videoscale keeps the picture's
  // proportions and chooses the height for the width asked for.
  g_autofree gchar* scale =
      max_width > 0
          ? g_strdup_printf(
                "! videoscale ! video/x-raw,width=%d,pixel-aspect-ratio=1/1 ",
                max_width)
          : g_strdup("");
  g_autofree gchar* description = g_strdup_printf(
      "uridecodebin uri=\"%s\" "
      "! videoconvert %s! jpegenc quality=80 ! appsink name=sink sync=false",
      uri.c_str(), scale);
  g_autoptr(GError) error = nullptr;
  g_autoptr(GstElement) pipeline = gst_parse_launch(description, &error);
  if (pipeline == nullptr) {
    return Fail(error != nullptr ? error->message
                                 : "the pipeline cannot be built");
  }
  g_autoptr(GstElement) element =
      gst_bin_get_by_name(GST_BIN(pipeline), "sink");
  gst_element_set_state(pipeline, GST_STATE_PAUSED);
  if (!Settle(pipeline)) {
    std::string problem =
        BusError(pipeline, "GStreamer cannot decode the video");
    gst_element_set_state(pipeline, GST_STATE_NULL);
    return Fail(problem);
  }
  gst_element_seek_simple(
      pipeline, GST_FORMAT_TIME,
      static_cast<GstSeekFlags>(
          GST_SEEK_FLAG_FLUSH |
          (exact ? GST_SEEK_FLAG_ACCURATE : GST_SEEK_FLAG_KEY_UNIT)),
      time_ms * GST_MSECOND);
  Settle(pipeline);
  g_autoptr(GstSample) sample =
      gst_app_sink_try_pull_preroll(GST_APP_SINK(element), kWait);
  if (sample == nullptr) {
    std::string problem = BusError(pipeline, "no frame at that time");
    gst_element_set_state(pipeline, GST_STATE_NULL);
    return Fail(problem);
  }
  g_autoptr(FlValue) answer = fl_value_new_map();
  GstBuffer* buffer = gst_sample_get_buffer(sample);
  GstMapInfo map;
  if (gst_buffer_map(buffer, &map, GST_MAP_READ)) {
    fl_value_set_string_take(answer, "jpeg",
                             fl_value_new_uint8_list(map.data, map.size));
    gst_buffer_unmap(buffer, &map);
  }
  if (GST_BUFFER_PTS_IS_VALID(buffer)) {
    fl_value_set_string_take(
        answer, "timeMs",
        fl_value_new_int((GST_BUFFER_PTS(buffer) + GST_MSECOND / 2) /
                         GST_MSECOND));
  }
  GstCaps* caps = gst_sample_get_caps(sample);
  if (caps != nullptr && gst_caps_get_size(caps) > 0) {
    GstStructure* structure = gst_caps_get_structure(caps, 0);
    gint width = 0;
    gint height = 0;
    gst_structure_get_int(structure, "width", &width);
    gst_structure_get_int(structure, "height", &height);
    fl_value_set_string_take(answer, "width", fl_value_new_int(width));
    fl_value_set_string_take(answer, "height", fl_value_new_int(height));
  }
  gst_element_set_state(pipeline, GST_STATE_NULL);
  return FL_METHOD_RESPONSE(fl_method_success_response_new(answer));
}

gint64 IntArg(FlValue* args, const char* name, gint64 fallback) {
  FlValue* value = fl_value_lookup_string(args, name);
  if (value == nullptr || fl_value_get_type(value) != FL_VALUE_TYPE_INT) {
    return fallback;
  }
  return fl_value_get_int(value);
}

}  // namespace

static void tom_media_extract_probe_plugin_handle_method_call(
    TomMediaExtractProbePlugin* self, FlMethodCall* method_call) {
  g_autoptr(FlMethodResponse) response = nullptr;
  const gchar* method = fl_method_call_get_name(method_call);
  FlValue* args = fl_method_call_get_args(method_call);
  FlValue* path = fl_value_get_type(args) == FL_VALUE_TYPE_MAP
                      ? fl_value_lookup_string(args, "path")
                      : nullptr;
  if (path == nullptr || fl_value_get_type(path) != FL_VALUE_TYPE_STRING) {
    response = FL_METHOD_RESPONSE(
        fl_method_error_response_new("arguments", "path is missing", nullptr));
    fl_method_call_respond(method_call, response, nullptr);
    return;
  }
  if (!gst_is_initialized()) {
    gst_init(nullptr, nullptr);
  }
  std::string uri = ToUri(fl_value_get_string(path));
  int rate = static_cast<int>(IntArg(args, "sampleRate", 16000));
  int channels = static_cast<int>(IntArg(args, "channels", 1));
  if (strcmp(method, "info") == 0) {
    response = Info(uri);
  } else if (strcmp(method, "audioToWav") == 0) {
    FlValue* out = fl_value_lookup_string(args, "out");
    response = AudioToWav(uri, fl_value_get_string(out), rate, channels);
  } else if (strcmp(method, "audioPcm") == 0) {
    response = AudioPcm(uri, rate, channels, IntArg(args, "startMs", 0),
                        IntArg(args, "durationMs", -1));
  } else if (strcmp(method, "frame") == 0) {
    FlValue* exact = fl_value_lookup_string(args, "exact");
    response = Frame(uri, IntArg(args, "timeMs", 0),
                     static_cast<int>(IntArg(args, "maxWidth", 0)),
                     exact == nullptr || fl_value_get_type(exact) !=
                                             FL_VALUE_TYPE_BOOL ||
                         fl_value_get_bool(exact));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }
  fl_method_call_respond(method_call, response, nullptr);
}

static void tom_media_extract_probe_plugin_dispose(GObject* object) {
  G_OBJECT_CLASS(tom_media_extract_probe_plugin_parent_class)->dispose(object);
}

static void tom_media_extract_probe_plugin_class_init(
    TomMediaExtractProbePluginClass* klass) {
  G_OBJECT_CLASS(klass)->dispose = tom_media_extract_probe_plugin_dispose;
}

static void tom_media_extract_probe_plugin_init(
    TomMediaExtractProbePlugin* self) {}

static void method_call_cb(FlMethodChannel* channel, FlMethodCall* method_call,
                           gpointer user_data) {
  TomMediaExtractProbePlugin* plugin =
      TOM_MEDIA_EXTRACT_PROBE_PLUGIN(user_data);
  tom_media_extract_probe_plugin_handle_method_call(plugin, method_call);
}

void tom_media_extract_probe_plugin_register_with_registrar(
    FlPluginRegistrar* registrar) {
  TomMediaExtractProbePlugin* plugin = TOM_MEDIA_EXTRACT_PROBE_PLUGIN(
      g_object_new(tom_media_extract_probe_plugin_get_type(), nullptr));

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel =
      fl_method_channel_new(fl_plugin_registrar_get_messenger(registrar),
                            "tom_media_probe/extract", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(
      channel, method_call_cb, g_object_ref(plugin), g_object_unref);

  g_object_unref(plugin);
}
