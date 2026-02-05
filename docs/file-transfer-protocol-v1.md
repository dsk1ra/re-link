# File Transfer Protocol v1

## Overview
This document defines the Version 1 protocol for peer-to-peer file transfer over WebRTC DataChannels. The goal is to support reliable, chunked, and backpressure-aware file transfers with minimal memory footprint.

## Architecture

### Channels
We use separate DataChannels to isolate control signals from bulk data. This ensures that control messages (like "cancel" or "pause") are not blocked by a large queue of file data.

| Label | ID (optional) | Reliability | Type | Purpose |
| :--- | :--- | :--- | :--- | :--- |
| `control` | 0 | Reliable, Ordered | Text (JSON) | Signaling (Offer, Answer, Cancel, Ack) |
| `file_transfer` | 1 | Reliable, Ordered | Binary | Bulk file data chunks |

### Messages (Control Channel)

All messages on the `control` channel are JSON objects with a `type` field.

#### 1. File Offer (Sender -> Receiver)
Sent to initiate a file transfer.

```json
{
  "type": "file_offer",
  "id": "uuid-v4-string",
  "name": "example.pdf",
  "size": 12345678, // bytes
  "mime": "application/pdf", // optional
  "sha256": "hash-string" // optional (for integrity check at end)
}
```

#### 2. File Accept (Receiver -> Sender)
Sent to accept the transfer. The sender should start sending chunks only after receiving this.

```json
{
  "type": "file_accept",
  "id": "uuid-v4-string"
}
```

#### 3. File Reject / Cancel (Receiver <-> Sender)
Sent to reject an offer or cancel an in-progress transfer.

```json
{
  "type": "file_cancel",
  "id": "uuid-v4-string",
  "reason": "user_declined" // optional
}
```

#### 4. File Complete (Sender -> Receiver)
Sent to indicate that all chunks have been queued. Note: Receiver must verify size/hash before considering it "done".

```json
{
  "type": "file_complete",
  "id": "uuid-v4-string"
}
```

### Data Transfer (File Channel)

- **Format:** Raw binary chunks.
- **Chunk Size:** 16 KiB to 64 KiB (Dynamic based on network). Start with **32 KiB**.
- **Framing:**
  - For v1, we assume *one file transfer at a time* per `file_transfer` channel.
  - This allows us to send raw bytes without a per-chunk header, maximizing throughput.
  - If multiplexing multiple files is needed later, we will add a binary header (ID + offset) or use separate channels.

### Flow Control (Backpressure)

To prevent memory exhaustion (OOM) on both Sender and Receiver:

1.  **Sender Side:**
    - Monitor `RTCDataChannel.bufferedAmount`.
    - If `bufferedAmount` > `HighWaterMark` (e.g., 1 MB), **PAUSE** reading from disk/sending.
    - When `onBufferedAmountLow` fires (threshold e.g., 256 KB), **RESUME** sending.

2.  **Receiver Side:**
    - Append incoming chunks directly to a temporary file on disk.
    - Do not accumulate chunks in RAM.

### Integrity

1.  **Checksum:** Sender calculates SHA-256 of the file (if feasible) or size check.
2.  **Verification:** Receiver calculates SHA-256 while writing or after completion.
3.  **Finalize:** If verification passes, rename temp file to final destination.

## State Machine

**Sender:**
`Idle` -> `Offering` -> `Transferring` -> `Finished`

**Receiver:**
`Idle` -> `Decision` (User Prompt) -> `Receiving` -> `Verifying` -> `Done`
