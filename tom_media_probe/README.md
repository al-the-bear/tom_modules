# tom_media_probe

The feasibility probe of the audio and video libraries planned for
`tom_modules` (webwork quest, todo group `audiovideo`): recording audio and
video, transcripts, audio analysis, and audio and frame extraction from
video, on macOS, Windows, Linux, iOS, Android and the web. The research and
the figures are in the webwork quest's `audiovideo_research.webwork.md`.

A probe, not a product: `publish_to: none`, and `buildkit_skip.yaml` keeps it
out of buildkit's scans and the workspace checks. BSD-3 like the modules.

## What it is

One screen per capability, opened from the menu, and an automated run per
capability that measures and writes a report.

| Capability | Screen | Automated run |
| --- | --- | --- |
| Recording | `lib/src/recording_screen.dart`: audio with device and format choice and a live level meter; video with camera choice and a preview | `lib/src/auto_run.dart`, started with `--dart-define=PROBE_AUTO=recording` |
| Extraction | `lib/src/extraction_screen.dart`: the sound and still frames out of a fixture, of the video recorded last, or of a file named by its path | `lib/src/extraction_auto_run.dart`, started with `--dart-define=PROBE_AUTO=extraction` |

### Recording: the candidates

| Platform | Audio | Video |
| --- | --- | --- |
| macOS | `record` | `camera_desktop` behind `camera`'s API, and `camera_macos` with its own API |
| iOS, Android, web | `record` | `camera` |
| Windows | `record` | `camera_desktop`; `camera_windows` by swapping the dependency (the two cannot be in one build: both register as `camera`'s Windows implementation) |
| Linux | `record` (starts `parecord` and `ffmpeg`) | `camera_desktop` (GStreamer) |

### Extraction: the plugin

No permissive package extracts sound and frames on all six platforms, so
the probe carries its own plugin, [extract/](extract/README.md)
(`tom_media_extract_probe`), over each platform's demuxers and decoders:
AVFoundation, `MediaExtractor` / `MediaCodec` / `MediaMetadataRetriever`,
the Media Foundation Source Reader, the system's GStreamer on Linux, and in
the browser Web Audio and a `<video>` drawn to a canvas.

The fixtures are in [assets/fixtures/](assets/fixtures/README.md); every
frame carries its own number, so a frame got back says which frame it is.

## The automated recording run

It asks for the microphone, lists the input devices and the formats the
platform offers, records every format for `PROBE_SECONDS` (start and stop
latency, file size, level events), reads a raw PCM stream, records from a
second microphone if there is one, then records video from up to two cameras
with a preview on screen, and on macOS once more with `camera_macos`.

| `--dart-define` | Meaning |
| --- | --- |
| `PROBE_AUTO=recording` | start the run instead of the menu |
| `PROBE_SECONDS=10` | seconds per format |
| `PROBE_SKIP=audio,video,camera_macos` | parts to leave out |
| `PROBE_LONG_SECONDS=3600` | add one long recording |
| `PROBE_LONG_KIND=audio` | what the long recording records: `audio` or `video` |
| `PROBE_KEEP=true` | keep the recorded files |
| `PROBE_EXIT=true` | end the application when the run is over (desktop) |

The report is printed as `PROBE_PART <n> <json part>` lines (Android's log
cuts long lines) and written as `recording_report.json` into the
application's temporary folder. `tool/save_report.py <log> <report.json>`
puts the parts together.

## The automated extraction run

For every fixture, for a video recorded just then with the first camera,
and for a long video if one is named: what the platform says about the
file, the sound as a WAV file (16 kHz mono, 44.1 kHz stereo) with its time,
three seconds of sound in memory (checked for 440 Hz), frames at six times
with *exact* and with *the nearest key frame is enough* (each checked for
its frame number), ten frames at an interval, and a strip of ten thumbnails.

| `--dart-define` | Meaning |
| --- | --- |
| `PROBE_AUTO=extraction` | start the run instead of the menu |
| `PROBE_LONG_FILE=<path>` | also measure this video (`tool/make_fixtures.sh long <out>` writes one of an hour) |
| `PROBE_SKIP=recorded,<fixture>` | parts to leave out |
| `PROBE_KEEP=true` | keep every frame as `frame_<video>_<exact\|key>_<ms>.jpg`; `tool/frame_numbers.py <folder>` reads their numbers where the run cannot (no graphics context, as over SSH) |
| `PROBE_EXIT=true` | end the application when the run is over (desktop) |

It is run like the recording run (below), with `PROBE_AUTO=extraction`; on
Linux `PROBE_RUN=extraction bash tool/linux_run.sh`. On macOS the
application is sandboxed: a long video has to lie in its container
(`~/Library/Containers/de.tom.tomMediaProbe/Data/tmp/`).

### Running it

Both runs: `tool/run_until_done.py <log> <seconds> <command…>` runs a command, copies
its output to the log and ends it once the run printed `PROBE_DONE`.

- **macOS, Windows, Linux:** `flutter build <platform> --release
  --dart-define=PROBE_AUTO=recording --dart-define=PROBE_EXIT=true`, then
  start the built application with its output in a file.
- **Linux over SSH:** `tool/linux_run.sh` builds, starts a private PulseAudio
  with two virtual microphones and runs the application on the X display in
  `PROBE_DISPLAY`. `record` needs `parecord` and `ffmpeg` on the `PATH`
  (`PROBE_PATH` adds a folder).
- **Web:** `flutter run -d chrome --dart-define=PROBE_AUTO=recording
  --web-browser-flag=--use-fake-ui-for-media-stream
  --web-browser-flag=--use-fake-device-for-media-stream` (debug mode: a
  release build prints nothing to the terminal).
- **iOS simulator:** `xcrun simctl privacy <device> grant microphone
  de.tom.tomMediaProbe`, then `flutter run -d <device>
  --dart-define=PROBE_AUTO=recording`. The simulator has no camera.
- **Android emulator:** build the APK with the define, install it, grant
  `RECORD_AUDIO` and `CAMERA` with `adb shell pm grant de.tom.tom_media_probe
  …`, start the activity and read `adb logcat -s flutter`.
