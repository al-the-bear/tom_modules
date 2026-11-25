import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

/// The fixture videos of `assets/fixtures/` (written by
/// `tool/make_fixtures.sh`): 10 seconds, 320x240, 30 frames a second, a key
/// frame every 2 seconds, a 440 Hz sine as sound.
const List<String> fixtures = <String>[
  'h264_aac.mp4',
  'hevc_aac.mov',
  'vp9_opus.webm',
  'h264_aac.mkv',
];

/// Frames a second of the fixtures.
const int fixtureFps = 30;

/// Frames between two key frames of the fixtures.
const int fixtureKeyInterval = 60;

/// Reads the frame number a fixture's frame carries in its top strip: 20
/// squares of 16x24 pixels in a 320x240 picture, square b white when bit b
/// of the number is set. Null when the picture cannot be decoded.
Future<int?> frameNumber(Uint8List jpeg) async {
  try {
    final ui.Codec codec = await ui.instantiateImageCodec(jpeg);
    final ui.FrameInfo frame = await codec.getNextFrame();
    final ui.Image image = frame.image;
    final ByteData? pixels = await image.toByteData();
    if (pixels == null) {
      return null;
    }
    final int y = (12 / 240 * image.height).floor();
    int number = 0;
    for (int bit = 0; bit < 20; bit++) {
      final int x = ((bit + 0.5) * 16 / 320 * image.width).floor();
      final int at = (y * image.width + x) * 4;
      final int light =
          pixels.getUint8(at) +
          pixels.getUint8(at + 1) +
          pixels.getUint8(at + 2);
      if (light > 384) {
        number |= 1 << bit;
      }
    }
    image.dispose();
    codec.dispose();
    return number;
  } on Object {
    return null;
  }
}

/// What a block of 16-bit mono samples sounds like: its level and its
/// frequency by counting zero crossings.
({double rmsDbfs, double frequency}) describeTone(
  Uint8List pcm,
  int sampleRate,
) {
  final ByteData data = ByteData.sublistView(pcm);
  final int count = pcm.lengthInBytes ~/ 2;
  if (count < 2) {
    return (rmsDbfs: -160, frequency: 0);
  }
  double sum = 0;
  int crossings = 0;
  int before = data.getInt16(0, Endian.little);
  for (int i = 0; i < count; i++) {
    final int sample = data.getInt16(i * 2, Endian.little);
    sum += sample * sample;
    if ((before < 0) != (sample < 0)) {
      crossings++;
    }
    before = sample;
  }
  final double rms = math.sqrt(sum / count) / 32768;
  return (
    rmsDbfs: rms > 0 ? 20 * math.log(rms) / math.ln10 : -160,
    frequency: crossings / 2 / (count / sampleRate),
  );
}
