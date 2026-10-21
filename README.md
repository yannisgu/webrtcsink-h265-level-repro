# webrtcsink: H.265 fails when the receiver offers a higher level than the encoder produces

In H.265 SDP, `level-id` and `tier-flag` give the **highest** level and tier
the receiver can decode (RFC 7798). webrtcsink (gst-plugins-rs) uses them as
the exact level and tier the encoder has to produce. Encoders choose these
values from the resolution, framerate and bitrate, so in practice the offer
almost never matches.

**Use case:** a browser plays an H.265 stream from `whepserversink` (or from any
webrtcsink signaller where the viewer sends the offer). The browser offers its
decoder's maximum, for example level 6.0. A 1080p30 encode is level 4.0, which
the browser can decode. webrtcsink rejects H.265 anyway: it falls back to
another codec, or rejects the m-line if H.265 is the only codec.

The tier has the same problem: encoders switch from main to high tier as the
bitrate goes up (nvh265enc at 1080p25 above about 12 Mbps; x265enc too, see
repro 1b).

## Repro 1: one pipeline

webrtcsink builds `encoder ! h265parse ! rtph265pay ! capsfilter(offer caps)`:

```sh
# level-id=180 (6.0): offered by the receiver -> not-negotiated
gst-launch-1.0 videotestsrc num-buffers=120 ! video/x-raw,format=I420,width=1920,height=1080 \
  ! x265enc ! h265parse ! rtph265pay ! 'application/x-rtp,level-id=(string)180,tier-flag=(string)0' ! fakesink

# level-id=120 (4.0): what x265enc produces for 1080p -> works
gst-launch-1.0 videotestsrc num-buffers=120 ! video/x-raw,format=I420,width=1920,height=1080 \
  ! x265enc ! h265parse ! rtph265pay ! 'application/x-rtp,level-id=(string)120,tier-flag=(string)0' ! fakesink
```

## Repro 1b: tier

x265enc also switches tier with the bitrate (level 4.0 at 1080p30: main tier
at 8 Mbps, high tier at 30 Mbps). A receiver that offers high tier can decode
main tier, but the 8 Mbps stream is still rejected:

```sh
# offer: level 4.0, high tier; stream: main tier at 8 Mbps -> not-negotiated
gst-launch-1.0 videotestsrc num-buffers=60 pattern=snow ! video/x-raw,format=I420,width=1920,height=1080,framerate=30/1 \
  ! x265enc bitrate=8000 option-string=level-idc=4 ! h265parse ! rtph265pay \
  ! 'application/x-rtp,level-id=(string)120,tier-flag=(string)1' ! fakesink
```

`bitrate=30000` (high tier) works with that offer. With a main-tier offer it's
the other way round, so with any fixed offer one of the two bitrates fails.

## Repro 2: whepserversink + curl

```sh
./whep-repro.sh
```

Answer with gst-plugin-webrtc 0.15.2:

```
a=rtpmap:96 H265/90000
a=fmtp:96 level-id=180;profile-id=1;tier-flag=0;tx-mode=SRST
a=inactive
```

Log: `No codec selected for media 0`, preceded by `rtph265pay ... failed to set
vps/sps/pps` and `not-negotiated` in the discovery pipeline.

With the fix, the answer is `a=sendonly` and the stream is sent.

Tested with GStreamer 1.28.7.
