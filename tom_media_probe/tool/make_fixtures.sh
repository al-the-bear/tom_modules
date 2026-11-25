#!/bin/bash
# Writes the probe's fixture videos into assets/fixtures/ with ffmpeg.
#
#   bash tool/make_fixtures.sh            the four 10-second fixtures
#   bash tool/make_fixtures.sh long <out> a one-hour MP4 (not kept in git)
#
# Every frame carries its own number: the top strip holds 20 squares of
# 16x24 pixels, square b white when bit b of the frame number is set. A
# frame got back from an extractor says which frame it is. 320x240, 30
# frames a second, a key frame every 60 frames (2 s); the sound is a 440 Hz
# sine at 44.1 kHz, stereo.
set -eu
cd "$(dirname "$0")/.."
bits=""
for b in $(seq 0 19); do
  bits="$bits,drawbox=x=$((b * 16)):y=0:w=16:h=24:color=white:t=fill:enable='eq(mod(floor(n/pow(2\,$b))\,2)\,1)'"
done
video() { # seconds
  echo "-f lavfi -i testsrc2=size=320x240:rate=30:duration=$1 -f lavfi -i sine=frequency=440:sample_rate=44100:duration=$1"
}
filter="drawbox=x=0:y=0:w=320:h=24:color=black:t=fill$bits,format=yuv420p"
common="-hide_banner -loglevel error -y"
gop="-g 60 -keyint_min 60 -sc_threshold 0"

if [ "${1:-}" = "long" ]; then
  # shellcheck disable=SC2046
  ffmpeg $common $(video 3600) -vf "$filter" -ac 2 -c:v libx264 -preset veryfast \
    -b:v 150k $gop -c:a aac -b:a 64k "$2"
  exit 0
fi

out=assets/fixtures
# shellcheck disable=SC2046
ffmpeg $common $(video 10) -vf "$filter" -ac 2 -c:v libx264 -b:v 300k $gop \
  -c:a aac -b:a 96k -movflags +faststart $out/h264_aac.mp4
# shellcheck disable=SC2046
ffmpeg $common $(video 10) -vf "$filter" -ac 2 -c:v libx265 -b:v 300k \
  -x265-params "keyint=60:min-keyint=60:scenecut=0:log-level=error" -tag:v hvc1 \
  -c:a aac -b:a 96k $out/hevc_aac.mov
# shellcheck disable=SC2046
ffmpeg $common $(video 10) -vf "$filter" -ac 2 -c:v libvpx-vp9 -b:v 300k $gop \
  -c:a libopus -b:a 64k $out/vp9_opus.webm
# shellcheck disable=SC2046
ffmpeg $common $(video 10) -vf "$filter" -ac 2 -c:v libx264 -b:v 300k $gop \
  -c:a aac -b:a 96k $out/h264_aac.mkv
ls -la $out
