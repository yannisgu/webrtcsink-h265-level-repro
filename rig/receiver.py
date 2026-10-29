#!/usr/bin/env python3
# WHEP receiver: offers H.265 with the given level-id and tier-flag, prints
# the answer's direction and the number of H.265 frames received.
# usage: receiver.py <whep-url> <level-id> <tier-flag> [seconds] [--pli]
#   --pli: ask for a keyframe until the first frame, like a browser's decoder
import sys
import urllib.request

import gi

gi.require_version("Gst", "1.0")
gi.require_version("GstWebRTC", "1.0")
gi.require_version("GstSdp", "1.0")
gi.require_version("GstVideo", "1.0")
from gi.repository import GLib, Gst, GstSdp, GstVideo, GstWebRTC  # noqa: E402

args = [a for a in sys.argv[1:] if not a.startswith("--")]
url, level, tier = args[0], args[1], args[2]
secs = int(args[3]) if len(args) > 3 else 15
pli = "--pli" in sys.argv

Gst.init(None)
pipe = Gst.Pipeline()
webrtc = Gst.ElementFactory.make("webrtcbin")
webrtc.set_property("bundle-policy", GstWebRTC.WebRTCBundlePolicy.MAX_BUNDLE)
pipe.add(webrtc)
loop = GLib.MainLoop()
frames = [0]

caps = Gst.Caps.from_string(
    "application/x-rtp,media=video,encoding-name=H265,clock-rate=90000,payload=96,"
    f"profile-id=(string)1,level-id=(string){level},tier-flag=(string){tier},tx-mode=(string)SRST"
)
webrtc.emit("add-transceiver", GstWebRTC.WebRTCRTPTransceiverDirection.RECVONLY, caps)


def on_pad(_, pad):
    if pad.direction != Gst.PadDirection.SRC:
        return
    bin_ = Gst.parse_bin_from_description("rtph265depay ! h265parse ! fakesink name=sink", True)
    pipe.add(bin_)
    bin_.sync_state_with_parent()
    pad.link(bin_.get_static_pad("sink"))

    def count(_pad, _info):
        frames[0] += 1
        return Gst.PadProbeReturn.OK

    bin_.get_by_name("sink").get_static_pad("sink").add_probe(Gst.PadProbeType.BUFFER, count)

    def request_keyframe():
        if frames[0] == 0:
            ev = GstVideo.video_event_new_upstream_force_key_unit(Gst.CLOCK_TIME_NONE, True, 0)
            bin_.get_static_pad("sink").send_event(ev)
        return frames[0] == 0

    if pli:
        GLib.timeout_add(1000, request_keyframe)


def on_gathering(*_):
    if webrtc.get_property("ice-gathering-state") != GstWebRTC.WebRTCICEGatheringState.COMPLETE:
        return
    offer = webrtc.get_property("local-description").sdp.as_text()
    req = urllib.request.Request(url, offer.encode(), {"Content-Type": "application/sdp"})
    answer = urllib.request.urlopen(req).read().decode()
    direction = [l for l in answer.splitlines() if l in ("a=sendonly", "a=inactive", "a=recvonly", "a=sendrecv")]
    print("answer:", direction[0] if direction else "?", flush=True)
    _, sdp = GstSdp.SDPMessage.new_from_text(answer)
    desc = GstWebRTC.WebRTCSessionDescription.new(GstWebRTC.WebRTCSDPType.ANSWER, sdp)
    webrtc.emit("set-remote-description", desc, Gst.Promise.new())


def on_offer(promise, _):
    # Keep the reply alive while the offer is in use
    reply = promise.get_reply()
    offer = reply.get_value("offer")
    webrtc.emit("set-local-description", offer, Gst.Promise.new())


webrtc.connect("pad-added", on_pad)
webrtc.connect("notify::ice-gathering-state", on_gathering)
webrtc.connect(
    "on-negotiation-needed",
    lambda _: webrtc.emit("create-offer", None, Gst.Promise.new_with_change_func(on_offer, None)),
)
pipe.set_state(Gst.State.PLAYING)
GLib.timeout_add_seconds(secs, loop.quit)
loop.run()
print("frames received:", frames[0])
pipe.set_state(Gst.State.NULL)
