#!/bin/bash
# webrtcsink answers: whepserversink serves 1080p30 H.265, receiver.py offers
# H.265 up to the given level and tier and counts the frames it gets.
# usage: answerer.sh <plugin.so|-> <port> <level-id> <tier-flag> <raw|BITRATE>
#   plugin.so: libgstrswebrtc.so to test, - for the installed one
#   raw: webrtcsink encodes; BITRATE: pre-encoded by x265enc at BITRATE kbit/s
# env: EXTRA (whepserversink properties), RXARGS (e.g. --pli), SDEBUG (GST_DEBUG)
DIR=$(cd "$(dirname "$0")" && pwd)
LIB=$1 PORT=$2 LVL=$3 TIER=$4 SRC=$5
LOAD=(); [ "$LIB" != - ] && LOAD=(--gst-plugin-load="$LIB")
CAPS="video/x-raw,format=I420,width=1920,height=1080,framerate=30/1"
if [ "$SRC" = raw ]; then ENC=(); else ENC=(! x265enc bitrate="$SRC" option-string=level-idc=4 key-int-max=30 ! h265parse config-interval=-1 ! video/x-h265,stream-format=byte-stream,alignment=au); fi
mkdir -p "$DIR/logs"; LOG="$DIR/logs/answerer-$PORT.log"
GST_DEBUG=${SDEBUG:-2} timeout 45 gst-launch-1.0 "${LOAD[@]}" videotestsrc is-live=true pattern=snow ! $CAPS "${ENC[@]}" \
  ! whepserversink video-caps=video/x-h265 $EXTRA signaller::host-addr=http://127.0.0.1:$PORT/ > "$LOG" 2>&1 &
for i in $(seq 60); do ss -ltn | grep -q ":$PORT " && break; sleep 0.5; done; sleep 2
timeout 30 python3 "$DIR/receiver.py" "http://127.0.0.1:$PORT/whep/endpoint" "$LVL" "$TIER" 15 $RXARGS 2>&1 | paste -sd' '
echo "   server not-negotiated: $(grep -ac not-negotiated "$LOG")"
pkill -P $$ timeout 2>/dev/null; wait
