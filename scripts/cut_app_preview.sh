#!/usr/bin/env bash
#
# cut_app_preview.sh — the edit behind AppStore/preview/voyage-preview.mp4.
#
# The App Store preview is two real captures from the simulator, cut together:
#
#   1. The opening: the cold-launch flyover into the Home globe, recorded with
#      `simctl launch` and no test runner attached. Launched under XCUITest,
#      the automation session starts in the same second as the app, and the
#      simulator recorder squeezes the flyover into a handful of frames.
#   2. The tour: `KEEP_RAW=1 TRIM_START=0 scripts/record_app_preview.sh` leaves
#      AppStore/preview/raw-capture.mp4, the booking through the takeoff roll.
#
# The cut keeps the motion and drops the test runner's waits (element lookups
# on the seat map cost about a second each), with short crossfades between
# segments. Segment times are seconds into each raw capture and change from
# take to take, so check them against a contact sheet before cutting:
#
#   ffmpeg -i AppStore/preview/raw-capture.mp4 -vf "fps=2,scale=80:-1,tile=20x4" -frames:v 1 sheet.png
#
#   scripts/cut_app_preview.sh --record-opening     # capture step 1
#   OPENING=2.55:6.0 GLOBE=6.6:13.8 BOARDING=16.6:22.3 TAKEOFF=23.3:31.5 scripts/cut_app_preview.sh
#
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIR="$REPO/AppStore/preview"
DEVICE="${VOYAGE_SIM_DEVICE:-iPhone 17}"
BUNDLE=com.patrickliu.voyage

UDID="$(xcrun simctl list devices available | sed -n "s/^ *${DEVICE} (\([0-9A-F-]*\)).*/\1/p" | head -1)"
[ -n "$UDID" ] || { echo "no available simulator named '$DEVICE'" >&2; exit 1; }

if [ "${1:-}" = "--record-opening" ]; then
  xcrun simctl boot "$UDID" 2>/dev/null || true
  xcrun simctl bootstatus "$UDID" -b >/dev/null
  xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
  # No interrupted-flight alert over the flyover (InterruptedFlightRecovery.key).
  DATA="$(xcrun simctl get_app_container "$UDID" "$BUNDLE" data)"
  plutil -remove voyage.inFlightRecord "$DATA/Library/Preferences/$BUNDLE.plist" >/dev/null 2>&1 || true
  xcrun simctl status_bar "$UDID" override --time 9:41 --batteryLevel 100 --batteryState charged \
    --wifiBars 3 --cellularBars 4 --operatorName "" >/dev/null 2>&1 || true
  trap 'xcrun simctl status_bar "$UDID" clear >/dev/null 2>&1' EXIT
  xcrun simctl io "$UDID" recordVideo --codec hevc --force "$DIR/opening-raw.mp4" >/dev/null 2>&1 &
  REC=$!
  sleep 2
  xcrun simctl launch "$UDID" "$BUNDLE" -AppleLanguages "(en)" -AppleLocale en_US \
    -VoyageHomeAirport SFO -VoyageShortFlights -VoyageSceneHour 10 -windowWorldMode illustrated >/dev/null
  sleep 7
  kill -INT "$REC"; wait "$REC" || true
  echo "wrote $DIR/opening-raw.mp4"
  exit 0
fi

: "${OPENING:?set OPENING=start:end (seconds in opening-raw.mp4)}"
: "${GLOBE:?set GLOBE=start:end (seconds in raw-capture.mp4)}"
: "${BOARDING:?set BOARDING=start:end}"
: "${TAKEOFF:?set TAKEOFF=start:end}"

len() { python3 -c "a,b=map(float,'$1'.split(':')); print(round(b-a,3))"; }
FADE=0.25
O=$(len "$OPENING"); G=$(len "$GLOBE"); B=$(len "$BOARDING")
OFF1=$(python3 -c "print(round($O-$FADE,3))")
OFF2=$(python3 -c "print(round($O+$G-2*$FADE,3))")
OFF3=$(python3 -c "print(round($O+$G+$B-3*$FADE,3))")
V="fps=30,scale=886:1920:flags=lanczos,format=yuv420p"

# App Store Connect rejects a preview without a stereo track (MOV_RESAVE_STEREO),
# so a silent one is muxed in, as in record_app_preview.sh.
ffmpeg -y -loglevel error -i "$DIR/opening-raw.mp4" -i "$DIR/raw-capture.mp4" \
  -f lavfi -i anullsrc=channel_layout=stereo:sample_rate=48000 -filter_complex "
[0:v]$V,trim=${OPENING},setpts=PTS-STARTPTS[o];
[1:v]$V,split=3[g][b][t];
[g]trim=${GLOBE},setpts=PTS-STARTPTS[g1];
[b]trim=${BOARDING},setpts=PTS-STARTPTS[b1];
[t]trim=${TAKEOFF},setpts=PTS-STARTPTS[t1];
[o][g1]xfade=transition=fade:duration=$FADE:offset=$OFF1[og];
[og][b1]xfade=transition=fade:duration=$FADE:offset=$OFF2[ogb];
[ogb][t1]xfade=transition=fade:duration=$FADE:offset=$OFF3[v]" \
  -map "[v]" -map 2:a -shortest -c:v libx264 -profile:v high -pix_fmt yuv420p -r 30 \
  -movflags +faststart -c:a aac -b:a 256k -ac 2 "$DIR/voyage-preview.mp4"
ffprobe -v error -show_entries stream=codec_type,width,height:format=duration -of default=nw=1 "$DIR/voyage-preview.mp4"
