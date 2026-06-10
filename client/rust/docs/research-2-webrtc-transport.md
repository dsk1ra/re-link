# Research 2: WebRTC Media Track for Screen Share Transport

## Current Pipeline Analysis

### Sender Side (screen_capture.rs)
```
H.264 NAL bytes → EncodeOutput::Nal { data, duration }
  → mpsc channel (capacity 8)
  → write_outputs task → Sample { data, duration }
  → TrackLocalStaticSample::write_sample()
  → (internal) RTP packetization with FU-A fragmentation
  → SRTP → UDP
```

### Receiver Side (webrtc.rs)
```
UDP → SRTP → RTP packets
  → TrackRemote::read_rtp() loop
  → SampleBuilder::push() + pop()  [ring buffer, max_late=512]
  → H264Packet depacketizer reassembles NALs
  → openh264 Decoder::decode()
  → YUV → RGBA (write_rgba8)
  → StreamSink<RawVideoFrame> → Flutter
```

## Identified Issues

### 1. SampleBuilder Ring Buffer Design

SampleBuilder uses a ring buffer indexed by `seq_num % capacity`. Even with
`max_late=512`, this is still vulnerable to collisions on very large keyframes
(512+ packets, which is unlikely but possible at high bitrates/resolutions).
The SampleBuilder also has known issues:
- RTP sequence number wrap causes spurious packet loss
- Visual artifacts with stable/low-motion video (pion/webrtc#2971)
- Cannot distinguish between "missing packet" and "late packet"

**Alternative**: Custom H.264 depacketizer that operates directly on the RTP
stream without a ring buffer. The H264Packet depacketizer can be used standalone
to reassemble NALs from FU-A fragments, with a simpler sequential state machine
that only needs to track the current frame's packets.

### 2. No NACK/PLI for Keyframe Recovery

The current code uses `register_default_interceptors()` which registers:
- **NACK**: Retransmission requests for lost packets
- **TWCC**: Transport-wide congestion control
- **RTCP Reports**: Sender/Receiver reports

This means NACK is enabled, so lost packets should be retransmitted. However,
there's no explicit PLI (Picture Loss Indication) handling — if the decoder
encounters corrupted frames, it doesn't request a new keyframe from the sender.
The sender has IDR period = `tier.fps` (1 second), so recovery takes up to
1 second after corruption.

**Recommendation**: Add a PLI feedback path — when the decoder fails (`Err(e)`),
send a PLI via RTCP to trigger an immediate keyframe.

### 3. RTP Packetization and MTU

WebRTC uses an RTP payload MTU of ~1200 bytes. The TrackLocalStaticSample
automatically fragments H.264 NALs into FU-A packets when they exceed the MTU.
This is correct behavior.

Previously, OpenH264 was configured with `max_slice_len(1150)` which created
many small NAL units — the encoder was doing fragmentation that the RTP
packetizer would then do again. This was removed in the prior session, which is
correct: let the RTP layer handle fragmentation.

### 4. Congestion Control & Bandwidth Adaptation

The current code has a manual quality tier adaptation system based on RTCP
receiver reports (`adapt_quality`). The webrtc-rs stack also has TWCC enabled
via `register_default_interceptors()`.

However, the two systems don't talk to each other:
- TWCC estimates available bandwidth at the receiver side
- `adapt_quality` reads loss fraction from RTCP receiver reports
- The encoder bitrate is set once at encoder creation based on the tier

**Recommendation**: Feed TWCC bandwidth estimates into the encoder's bitrate
configuration dynamically. The current tier-based system is reasonable but
coarse-grained (5 fixed tiers vs. continuous adaptation).

### 5. No Sender-Side Pacer

WebRTC best practice is to pace outgoing RTP packets to avoid bursty
transmission that can overwhelm network buffers. A keyframe at 1080p produces
~100-200KB of data, which without pacing gets blasted as ~100+ UDP packets in
microseconds, causing switch/router buffer overflow and packet loss.

The webrtc-rs stack does not include a built-in pacer. This is a significant
gap for screen sharing where keyframes are large and bursty.

## WebRTC Library Alternatives

### webrtc-rs (current)
- **Pros**: Full Pion port, familiar API, TrackLocal/TrackRemote abstraction,
  interceptor system for NACK/TWCC
- **Cons**: Many Arc<Mutex<>> internally, async callback model with lock
  contention, SampleBuilder has known bugs, not actively maintained (last
  significant updates 2023)
- **Risk**: The project has low maintenance activity

### str0m
- **Pros**: Sans-IO design (no internal threads, no locks, no Arc), 2.8x faster
  than webrtc-rs, ~48% less memory, actively maintained, clean RTP/frame API
- **Cons**: Different API paradigm (poll-based, not callback-based), significant
  migration effort, less community adoption
- **Assessment**: Better architecture but massive migration cost. Not worth it
  for fixing the current performance issue. Worth considering for a future rewrite.

### RustRTC
- **Pros**: 2.8x faster, 48% less memory vs webrtc-rs
- **Cons**: Newer, less battle-tested

## Key Recommendations for Transport Layer

### Quick Wins (no library change needed)
1. **PLI feedback loop**: On decode error, request keyframe via PLI
2. **Shorter IDR period for error recovery**: Already done (1s)
3. **SDP fmtp line**: Already done (packetization-mode=1, profile-level-id=42001f)

### Medium Effort
4. **Custom H.264 depacketizer**: Replace SampleBuilder with a stateful
   depacketizer that accumulates FU-A fragments per-timestamp and yields
   complete access units. Eliminates the ring buffer entirely.
5. **Dynamic bitrate from RTCP**: Instead of fixed tier bitrates, read the TWCC
   bandwidth estimate and set the encoder bitrate continuously.

### Future (requires library change)
6. **Consider str0m**: If performance remains insufficient, migrate to str0m
   for its fundamentally better architecture (no locks, no async callbacks).

## WebRTC Transport: UDP vs TCP

WebRTC media always prefers UDP. TCP introduces head-of-line blocking — a single
lost packet stalls all subsequent packets until retransmission. For real-time
screen sharing, it's better to drop a frame than to freeze waiting for a
retransmission that arrives too late.

The current stack correctly uses UDP for media transport. The NACK interceptor
handles retransmissions for recently lost packets (within the jitter buffer
window), and PLI handles catastrophic loss by requesting a new keyframe.

## Sources

- [webrtc-rs TrackLocalStaticSample](https://docs.rs/webrtc/latest/webrtc/track/track_local/track_local_static_sample/struct.TrackLocalStaticSample.html)
- [str0m](https://github.com/algesten/str0m)
- [Pion SampleBuilder issues](https://github.com/pion/webrtc/issues/2971)
- [WebRTC NACK/PLI/FIR](https://webrtcforthecurious.com/docs/06-media-communication/)
- [TWCC](https://flussonic.com/blog/news/transport-cc)
- [webrtc-rs interceptor_registry](https://docs.rs/webrtc/0.3.3/webrtc/api/interceptor_registry/index.html)
- [Why prefer UDP for WebRTC](https://bloggeek.me/why-you-should-prefer-udp-over-tcp-for-your-webrtc-sessions/)
- [H.264 RTP packetization](https://webrtchacks.com/what-i-learned-about-h-264-for-webrtc-video-tim-panton/)
