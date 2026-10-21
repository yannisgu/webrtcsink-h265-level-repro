#!/bin/sh
# Serve 1080p H.265 over WHEP and post a receiver offer for H.265 up to
# level 6.0 (level-id=180). x265enc produces level 4.0, which the receiver
# can decode, but webrtcsink answers the m-line with a=inactive.
gst-launch-1.0 videotestsrc is-live=true \
  ! video/x-raw,format=I420,width=1920,height=1080,framerate=30/1 \
  ! whepserversink video-caps=video/x-h265 signaller::host-addr=http://127.0.0.1:18080/ &
PID=$!
sleep 3
curl -s -X POST -H 'Content-Type: application/sdp' --data-binary @offer.sdp \
  http://127.0.0.1:18080/whep/endpoint | grep -E '^a=(rtpmap|fmtp|inactive|sendonly)'
kill $PID
