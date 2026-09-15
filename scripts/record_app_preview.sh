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
SECONDS_TO_RECORD="${SECONDS_TO_RECORD:-32}"
# Seconds cut from the front of the capture: the recorder starts before launch,
# so this is the springboard lead-in before the flyover. KEEP_RAW=1 keeps the
# untrimmed capture for re-timing.
TRIM_START="${TRIM_START:-2.5}"
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
# Whatever happens below, stop the tour and the recorder and put the status
# bar back, or the next QA capture on this simulator still says 9:41.
TOUR_PID=""; REC_PID=""
trap 'kill $TOUR_PID $REC_PID 2>/dev/null; xcrun simctl status_bar "$UDID" clear >/dev/null 2>&1; rm -f "$MARKER"' EXIT

# The tour's long hold ends with the app killed mid-flight, and the next launch
# then opens on the interrupted-flight alert, right over the launch flyover.
# Clear that record (InterruptedFlightRecovery.key) rather than reinstalling:
# a fresh install also resets location access, and its prompt lands on the
# flyover too. The grant only sticks to an installed app, so the very first
# take on a new simulator may still show it.
xcrun simctl terminate "$UDID" com.patrickliu.voyage >/dev/null 2>&1 || true
APP_DATA="$(xcrun simctl get_app_container "$UDID" com.patrickliu.voyage data 2>/dev/null || true)"
if [ -n "$APP_DATA" ] && [ -f "$APP_DATA/Library/Preferences/com.patrickliu.voyage.plist" ]; then
  plutil -remove voyage.inFlightRecord "$APP_DATA/Library/Preferences/com.patrickliu.voyage.plist" >/dev/null 2>&1 || true
fi
xcrun simctl privacy "$UDID" grant location com.patrickliu.voyage >/dev/null 2>&1 || true

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

# HEVC: with h264 the recorder dropped the launch flyover's swoop frames
# while the app and the test runner were both starting up.
echo "==> recording ${SECONDS_TO_RECORD}s"
xcrun simctl io "$UDID" recordVideo --codec "${RECORD_CODEC:-hevc}" --force "$RAW" &
REC_PID=$!
sleep "$SECONDS_TO_RECORD"
kill -INT "$REC_PID"
wait "$REC_PID" || true
wait "$TOUR_PID" || echo "    (tour reported a failure after the recording; the clip is still usable — check $OUT_DIR/tour.log)"

echo "==> scaling to 886x1920 at 30 fps"
# Simulator captures have no audio track, and App Store Connect rejects a
# preview without one (asset state FAILED, code MOV_RESAVE_STEREO), so a
# silent stereo AAC track is muxed in.
ffmpeg -y -loglevel error -ss "$TRIM_START" -i "$RAW" -f lavfi -i anullsrc=channel_layout=stereo:sample_rate=48000 \
  -t 29.5 -vf "scale=886:1920:flags=lanczos,format=yuv420p" -r 30 \
  -c:v libx264 -profile:v high -pix_fmt yuv420p -movflags +faststart \
  -c:a aac -b:a 256k -ac 2 -shortest \
  "$OUT"
[ -n "${KEEP_RAW:-}" ] || rm -f "$RAW"
rm -f "$MARKER"
xcrun simctl status_bar "$UDID" clear >/dev/null 2>&1 || true
ffprobe -v error -select_streams v:0 -show_entries stream=width,height,r_frame_rate:format=duration -of default=nw=1 "$OUT"
echo "wrote $OUT"
