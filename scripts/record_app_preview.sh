#!/usr/bin/env bash
#
# record_app_preview.sh — record the App Store preview clip from the simulator.
#
# Runs DemoReelUITests/testAppPreview, starts `simctl recordVideo` when the test
# signals that the home globe has settled (QA/preview-ready), records for
# $SECONDS_TO_RECORD seconds, then scales the capture to the 886x1920 portrait
# size App Store Connect accepts for every current iPhone preview slot.
#
#   scripts/record_app_preview.sh                # writes AppStore/preview/voyage-preview.mp4
#   scripts/record_app_preview.sh --device 'iPhone 17'
#
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO"

DEVICE="${VOYAGE_SIM_DEVICE:-iPhone 17}"
SECONDS_TO_RECORD="${SECONDS_TO_RECORD:-29}"
OUT_DIR="$REPO/AppStore/preview"
RAW="$OUT_DIR/raw-capture.mp4"
OUT="$OUT_DIR/voyage-preview.mp4"
MARKER="$REPO/QA/preview-ready"

while [ $# -gt 0 ]; do
  case "$1" in
    --device) shift; DEVICE="$1" ;;
    *) echo "unknown argument: $1" >&2; exit 1 ;;
  esac
  shift
done

command -v ffmpeg >/dev/null || { echo "ffmpeg is required (brew install ffmpeg)" >&2; exit 1; }
mkdir -p "$OUT_DIR" "$REPO/QA"
rm -f "$MARKER" "$RAW"

UDID="$(xcrun simctl list devices available | sed -n "s/^ *${DEVICE} (\([0-9A-F-]*\)).*/\1/p" | head -1)"
[ -n "$UDID" ] || { echo "no available simulator named '$DEVICE'" >&2; exit 1; }
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >/dev/null
# The status bar Apple's own previews wear; cleared again at the end.
xcrun simctl status_bar "$UDID" override --time 9:41 --batteryLevel 100 --batteryState charged --wifiBars 3 --cellularBars 4 --operatorName "" >/dev/null 2>&1 || true

echo "==> driving the preview tour on $DEVICE"
xcodebuild -project Voyage.xcodeproj -scheme Voyage \
  -destination "platform=iOS Simulator,id=$UDID" \
  test -only-testing:VoyageUITests/DemoReelUITests/testAppPreview \
  > "$OUT_DIR/tour.log" 2>&1 &
TOUR_PID=$!

echo "==> waiting for the globe to settle"
for _ in $(seq 1 240); do
  [ -f "$MARKER" ] && break
  kill -0 "$TOUR_PID" 2>/dev/null || { echo "tour exited before the marker — see $OUT_DIR/tour.log" >&2; exit 1; }
  sleep 0.5
done
[ -f "$MARKER" ] || { echo "marker never appeared — see $OUT_DIR/tour.log" >&2; kill "$TOUR_PID" 2>/dev/null || true; exit 1; }

echo "==> recording ${SECONDS_TO_RECORD}s"
xcrun simctl io "$UDID" recordVideo --codec h264 --force "$RAW" &
REC_PID=$!
sleep "$SECONDS_TO_RECORD"
kill -INT "$REC_PID"
wait "$REC_PID" || true
wait "$TOUR_PID" || echo "    (tour reported a failure after the recording; the clip is still usable — check $OUT_DIR/tour.log)"

echo "==> scaling to 886x1920 at 30 fps"
# Simulator captures have no audio track; App Store Connect accepts silent previews.
ffmpeg -y -loglevel error -i "$RAW" \
  -t 30 -vf "scale=886:1920:flags=lanczos,format=yuv420p" -r 30 \
  -c:v libx264 -profile:v high -pix_fmt yuv420p -movflags +faststart -an \
  "$OUT"
rm -f "$RAW" "$MARKER"
xcrun simctl status_bar "$UDID" clear >/dev/null 2>&1 || true
ffprobe -v error -select_streams v:0 -show_entries stream=width,height,r_frame_rate:format=duration -of default=nw=1 "$OUT"
echo "wrote $OUT"
