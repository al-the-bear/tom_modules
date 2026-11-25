import AVFoundation
import ImageIO

#if os(iOS)
  import Flutter
#else
  import FlutterMacOS
#endif

private struct ExtractError: Error, CustomStringConvertible {
  let description: String
  init(_ text: String) { description = text }
}

/// Audio and still frames out of a video with AVFoundation: `AVAssetReader`
/// decodes the sound to PCM at the rate and channel count asked for,
/// `AVAssetImageGenerator` returns a frame at a time.
public class TomMediaExtractProbePlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    #if os(iOS)
      let messenger = registrar.messenger()
    #else
      let messenger = registrar.messenger
    #endif
    let channel = FlutterMethodChannel(
      name: "tom_media_probe/extract", binaryMessenger: messenger)
    registrar.addMethodCallDelegate(TomMediaExtractProbePlugin(), channel: channel)
  }

  private let queue = DispatchQueue(label: "tom_media_probe.extract", qos: .userInitiated)

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    guard let path = args["path"] as? String else {
      result(FlutterError(code: "arguments", message: "path is missing", details: nil))
      return
    }
    let url = path.hasPrefix("file:") ? URL(string: path)! : URL(fileURLWithPath: path)
    let rate = args["sampleRate"] as? Int ?? 16000
    let channels = args["channels"] as? Int ?? 1
    queue.async {
      do {
        let value: Any
        switch call.method {
        case "info":
          value = try self.info(url)
        case "audioToWav":
          value = try self.audioToWav(
            url, out: args["out"] as? String ?? "", rate: rate, channels: channels)
        case "audioPcm":
          var data = Data()
          _ = try self.readAudio(
            url, rate: rate, channels: channels, startMs: args["startMs"] as? Int ?? 0,
            durationMs: args["durationMs"] as? Int
          ) { data.append($0) }
          value = FlutterStandardTypedData(bytes: data)
        case "frame":
          value = try self.frame(
            url, timeMs: args["timeMs"] as? Int ?? 0, maxWidth: args["maxWidth"] as? Int ?? 0,
            exact: args["exact"] as? Bool ?? true)
        default:
          DispatchQueue.main.async { result(FlutterMethodNotImplemented) }
          return
        }
        DispatchQueue.main.async { result(value) }
      } catch {
        DispatchQueue.main.async {
          result(FlutterError(code: "extract", message: "\(error)", details: nil))
        }
      }
    }
  }

  private func fourCharacters(_ track: AVAssetTrack) -> String? {
    guard let first = track.formatDescriptions.first else { return nil }
    let code = CMFormatDescriptionGetMediaSubType(first as! CMFormatDescription)
    let characters = [24, 16, 8, 0].map { shift in
      Character(UnicodeScalar(UInt8(truncatingIfNeeded: code >> UInt32(shift))))
    }
    return String(characters).trimmingCharacters(in: .whitespaces)
  }

  private func info(_ url: URL) throws -> [String: Any] {
    let asset = AVURLAsset(url: url)
    let video = asset.tracks(withMediaType: .video).first
    let audio = asset.tracks(withMediaType: .audio).first
    if video == nil, audio == nil {
      throw ExtractError("AVFoundation finds no audio or video track in this file")
    }
    var out: [String: Any] = [
      "durationMs": Int(CMTimeGetSeconds(asset.duration) * 1000),
      "hasVideo": video != nil,
      "hasAudio": audio != nil,
    ]
    if let video = video {
      let size = video.naturalSize.applying(video.preferredTransform)
      out["width"] = Int(abs(size.width))
      out["height"] = Int(abs(size.height))
      out["fps"] = Double(video.nominalFrameRate)
      if let codec = fourCharacters(video) { out["videoCodec"] = codec }
    }
    if let audio = audio {
      if let codec = fourCharacters(audio) { out["audioCodec"] = codec }
      if let first = audio.formatDescriptions.first,
        let basic = CMAudioFormatDescriptionGetStreamBasicDescription(
          first as! CMAudioFormatDescription)?.pointee
      {
        out["sampleRate"] = Int(basic.mSampleRate)
        out["channels"] = Int(basic.mChannelsPerFrame)
      }
    }
    return out
  }

  /// Decodes the sound and hands every block of 16-bit samples to `sink`.
  private func readAudio(
    _ url: URL, rate: Int, channels: Int, startMs: Int, durationMs: Int?,
    sink: (Data) throws -> Void
  ) throws -> Int {
    let asset = AVURLAsset(url: url)
    guard let track = asset.tracks(withMediaType: .audio).first else {
      throw ExtractError("the file has no audio track AVFoundation can read")
    }
    let reader = try AVAssetReader(asset: asset)
    let settings: [String: Any] = [
      AVFormatIDKey: kAudioFormatLinearPCM,
      AVSampleRateKey: rate,
      AVNumberOfChannelsKey: channels,
      AVLinearPCMBitDepthKey: 16,
      AVLinearPCMIsFloatKey: false,
      AVLinearPCMIsBigEndianKey: false,
      AVLinearPCMIsNonInterleaved: false,
    ]
    let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
    output.alwaysCopiesSampleData = false
    reader.add(output)
    if startMs > 0 || durationMs != nil {
      let duration =
        durationMs.map { CMTime(value: Int64($0), timescale: 1000) } ?? CMTime.positiveInfinity
      reader.timeRange = CMTimeRange(
        start: CMTime(value: Int64(startMs), timescale: 1000), duration: duration)
    }
    guard reader.startReading() else {
      throw reader.error ?? ExtractError("the reader does not start")
    }
    var bytes = 0
    while let sample = output.copyNextSampleBuffer() {
      guard let block = CMSampleBufferGetDataBuffer(sample) else { continue }
      let length = CMBlockBufferGetDataLength(block)
      var data = Data(count: length)
      data.withUnsafeMutableBytes { pointer in
        _ = CMBlockBufferCopyDataBytes(
          block, atOffset: 0, dataLength: length, destination: pointer.baseAddress!)
      }
      try sink(data)
      bytes += length
    }
    if reader.status == .failed {
      throw reader.error ?? ExtractError("reading the audio failed")
    }
    return bytes
  }

  private func wavHeader(dataBytes: Int, rate: Int, channels: Int) -> Data {
    var header = Data()
    func append32(_ value: Int) {
      let little = UInt32(truncatingIfNeeded: value).littleEndian
      withUnsafeBytes(of: little) { header.append(contentsOf: $0) }
    }
    func append16(_ value: Int) {
      let little = UInt16(truncatingIfNeeded: value).littleEndian
      withUnsafeBytes(of: little) { header.append(contentsOf: $0) }
    }
    header.append(contentsOf: Array("RIFF".utf8))
    append32(36 + dataBytes)
    header.append(contentsOf: Array("WAVEfmt ".utf8))
    append32(16)
    append16(1)
    append16(channels)
    append32(rate)
    append32(rate * channels * 2)
    append16(channels * 2)
    append16(16)
    header.append(contentsOf: Array("data".utf8))
    append32(dataBytes)
    return header
  }

  private func audioToWav(_ url: URL, out: String, rate: Int, channels: Int) throws -> [String: Any]
  {
    FileManager.default.createFile(atPath: out, contents: nil)
    guard let file = FileHandle(forWritingAtPath: out) else {
      throw ExtractError("cannot write \(out)")
    }
    defer { file.closeFile() }
    file.write(wavHeader(dataBytes: 0, rate: rate, channels: channels))
    let bytes = try readAudio(url, rate: rate, channels: channels, startMs: 0, durationMs: nil) {
      file.write($0)
    }
    file.seek(toFileOffset: 0)
    file.write(wavHeader(dataBytes: bytes, rate: rate, channels: channels))
    return ["frames": bytes / (2 * channels), "sampleRate": rate, "channels": channels]
  }

  private func frame(_ url: URL, timeMs: Int, maxWidth: Int, exact: Bool) throws -> [String: Any] {
    let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
    generator.appliesPreferredTrackTransform = true
    if maxWidth > 0 {
      generator.maximumSize = CGSize(width: maxWidth, height: maxWidth * 8)
    }
    if exact {
      generator.requestedTimeToleranceBefore = .zero
      generator.requestedTimeToleranceAfter = .zero
    }
    var actual = CMTime.zero
    let image = try generator.copyCGImage(
      at: CMTime(value: Int64(timeMs), timescale: 1000), actualTime: &actual)
    let data = NSMutableData()
    guard
      let destination = CGImageDestinationCreateWithData(
        data, "public.jpeg" as CFString, 1, nil)
    else {
      throw ExtractError("no JPEG encoder")
    }
    CGImageDestinationAddImage(
      destination, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
    guard CGImageDestinationFinalize(destination) else {
      throw ExtractError("the JPEG could not be written")
    }
    return [
      "jpeg": FlutterStandardTypedData(bytes: data as Data),
      "timeMs": Int((CMTimeGetSeconds(actual) * 1000).rounded()),
      "width": image.width,
      "height": image.height,
    ]
  }
}
