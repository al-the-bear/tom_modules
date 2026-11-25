#!/bin/bash
# Builds and runs the automated recording probe on a Linux machine that has
# no sound server running in the calling session (a server reached by SSH):
# a private PulseAudio with two virtual sources standing in for two
# microphones (record_linux leaves monitor sources out), on the X display
# given in PROBE_DISPLAY (default :10). PROBE_PATH is put in front of PATH
# (a folder holding an ffmpeg, where none is installed).
#
#   bash tool/linux_run.sh [extra flutter build arguments]
#
# The log is build/probe/linux.log; tool/save_report.py cuts the report out.
set -u
cd "$(dirname "$0")/.."
export PATH=${PROBE_PATH:+$PROBE_PATH:}/opt/flutter/bin:$PATH
export XDG_RUNTIME_DIR="$HOME/.cache/tom_media_probe_run"
mkdir -p "$XDG_RUNTIME_DIR" build/probe
chmod 700 "$XDG_RUNTIME_DIR"
export DISPLAY="${PROBE_DISPLAY:-:10}"

if ! flutter build linux --release --dart-define=PROBE_AUTO=recording \
    --dart-define=PROBE_EXIT=true "$@" > build/probe/linux_build.log 2>&1; then
  tail -40 build/probe/linux_build.log
  exit 1
fi
tail -2 build/probe/linux_build.log

pulseaudio -n --daemonize=no --exit-idle-time=-1 \
  --load="module-native-protocol-unix" \
  --load="module-null-sink sink_name=probe" \
  --load="module-null-sink sink_name=probe2" \
  --load="module-remap-source master=probe.monitor source_name=probe_mic source_properties=device.description=ProbeMicrophone" \
  --load="module-remap-source master=probe2.monitor source_name=probe_mic2 source_properties=device.description=ProbeMicrophone2" > build/probe/pulse.log 2>&1 &
PULSE=$!
sleep 2
pactl info | grep -E "Server Name|Default Source"
pactl set-default-source probe_mic
pactl list short sources
command -v ffmpeg parecord gst-launch-1.0

python3 tool/run_until_done.py build/probe/linux.log "${PROBE_LIMIT:-300}" \
  build/linux/x64/release/bundle/tom_media_probe
kill "$PULSE"
grep -o "PROBE_LOG.*" build/probe/linux.log
grep -v PROBE_ build/probe/linux.log | tail -15
