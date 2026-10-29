#!/bin/bash
# webrtcsink offers: whipclientsink sends 1080p30 H.265 to whipserversrc,
# which counts the frames it gets.
# usage: offerer.sh <plugin.so|-> <port> <raw|BITRATE>
DIR=$(cd "$(dirname "$0")" && pwd)
LIB=$1 PORT=$2 SRC=$3
LOAD=(); [ "$LIB" != - ] && LOAD=(--gst-plugin-load="$LIB")
CAPS="video/x-raw,format=I420,width=1920,height=1080,framerate=30/1"
if [ "$SRC" = raw ]; then ENC=(); else ENC=(! x265enc bitrate="$SRC" option-string=level-idc=4 key-int-max=30 ! h265parse config-interval=-1 ! video/x-h265,stream-format=byte-stream,alignment=au); fi
mkdir -p "$DIR/logs"; L="$DIR/logs/offerer-$PORT"
GST_DEBUG=2 timeout 30 gst-launch-1.0 -v "${LOAD[@]}" whipserversrc video-codecs='<H265>' signaller::host-addr=http://127.0.0.1:$PORT/ \
  ! rtph265depay ! h265parse ! fakesink silent=false > "$L-rx.log" 2>&1 &
sleep 3
GST_DEBUG=2 timeout 24 gst-launch-1.0 "${LOAD[@]}" videotestsrc is-live=true pattern=snow ! $CAPS "${ENC[@]}" \
  ! whipclientsink video-caps=video/x-h265 signaller::whip-endpoint=http://127.0.0.1:$PORT/whip/endpoint > "$L-tx.log" 2>&1
wait
echo "frames received: $(grep -ac 'last-message = chain' "$L-rx.log") | not-negotiated: $(grep -ac not-negotiated "$L-tx.log")"
