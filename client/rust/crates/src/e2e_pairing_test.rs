//! End-to-end pairing reproduction against a locally running signaling server.
//! Mirrors the Flutter flow: rendezvous init/join, encrypted mailbox signaling,
//! offer/answer/ICE exchange, and the 100ms event poll loop (including the
//! inline get_file_buffered_amount call the Dart manager performs each poll).

use crate::api::connection::*;
use crate::api::webrtc::*;
use serde_json::json;
use std::collections::HashSet;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpStream;

const SERVER: &str = "127.0.0.1:8080";

async fn http_post(
    path: &str,
    body: serde_json::Value,
) -> anyhow::Result<(u16, serde_json::Value)> {
    let body_str = body.to_string();
    let req = format!(
        "POST {path} HTTP/1.1\r\nHost: {SERVER}\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body_str}",
        body_str.len()
    );
    let mut stream = TcpStream::connect(SERVER).await?;
    stream.write_all(req.as_bytes()).await?;
    let mut resp = Vec::new();
    stream.read_to_end(&mut resp).await?;
    let resp = String::from_utf8_lossy(&resp).to_string();
    let status: u16 = resp
        .split_whitespace()
        .nth(1)
        .and_then(|s| s.parse().ok())
        .ok_or_else(|| anyhow::anyhow!("bad http response: {resp}"))?;
    let body_part = resp
        .split("\r\n\r\n")
        .nth(1)
        .unwrap_or("")
        .trim()
        .to_string();
    // strip possible chunked-encoding wrappers by finding the json braces
    let json_val = if let (Some(start), Some(end)) = (body_part.find('{'), body_part.rfind('}')) {
        serde_json::from_str(&body_part[start..=end]).unwrap_or(serde_json::Value::Null)
    } else {
        serde_json::Value::Null
    };
    Ok((status, json_val))
}

async fn send_signal(mailbox_id: &str, k_sig: &str, msg: serde_json::Value) -> anyhow::Result<()> {
    let ct = connection_encrypt(k_sig.to_string(), msg.to_string().into_bytes())?;
    let (status, _) = http_post(
        "/connection/send",
        json!({"mailbox_id": mailbox_id, "ciphertext_b64": ct}),
    )
    .await?;
    anyhow::ensure!(status == 202, "send_signal status {status}");
    Ok(())
}

async fn recv_signals(
    mailbox_id: &str,
    k_sig: &str,
    seen: &mut HashSet<String>,
) -> anyhow::Result<Vec<serde_json::Value>> {
    let (status, body) = http_post(
        "/connection/recv",
        json!({"mailbox_id": mailbox_id, "ciphertext_b64": ""}),
    )
    .await?;
    anyhow::ensure!(status == 200, "recv status {status}");
    let mut out = Vec::new();
    if let Some(messages) = body.get("messages").and_then(|m| m.as_array()) {
        for m in messages {
            let ct = m
                .get("ciphertext_b64")
                .and_then(|v| v.as_str())
                .unwrap_or("");
            if ct.is_empty() || !seen.insert(ct.to_string()) {
                continue;
            }
            let pt = connection_decrypt(k_sig.to_string(), ct.to_string())?;
            out.push(serde_json::from_slice(&pt)?);
        }
    }
    Ok(out)
}

/// One iteration of the Dart `_drainRustEvents` poll, faithfully including the
/// `getFileBufferedAmount` await that runs after every drain.
async fn poll_peer(
    conn_id: &str,
    my_mailbox: &str,
    k_sig: &str,
    peer_conn_id: &str,
    connected: &mut bool,
) -> anyhow::Result<()> {
    let events = drain_events(conn_id.to_string()).await?;
    for event in events {
        match event {
            WebRtcEvent::LocalIceCandidate { candidate } => {
                send_signal(
                    my_mailbox,
                    k_sig,
                    json!({"type": "ice", "data": {
                        "candidate": candidate.candidate,
                        "sdpMid": candidate.sdp_mid,
                        "sdpMLineIndex": candidate.sdp_mline_index,
                    }}),
                )
                .await?;
            }
            WebRtcEvent::ConnectionStateChanged { state } => {
                println!("[{conn_id}] state: {state}");
                if state == "connected" {
                    *connected = true;
                }
            }
            WebRtcEvent::DataChannelStateChanged { label, state } => {
                println!("[{conn_id}] channel {label}: {state}");
            }
            _ => {}
        }
    }
    let _ = peer_conn_id;
    // Dart: _lastFileBufferedAmount = await getFileBufferedAmount(...)
    let t0 = std::time::Instant::now();
    let res = get_file_buffered_amount(conn_id.to_string()).await;
    let elapsed = t0.elapsed();
    if elapsed > std::time::Duration::from_millis(500) {
        println!(
            "[{conn_id}] !!! get_file_buffered_amount blocked for {elapsed:?} (result: {})",
            match &res {
                Ok(v) => format!("ok {v}"),
                Err(e) => format!("err {e}"),
            }
        );
    }
    Ok(())
}

/// Requires a local signaling server: start Redis on :6379, then run
/// `SIGNALING_PUBLIC_URL=http://127.0.0.1:8080 SIGNALING_REDIS_REQUIRE_TLS=false cargo run`
/// in server/rust. Then: `cargo test --lib e2e_pairing -- --ignored --nocapture`
#[tokio::test(flavor = "multi_thread")]
#[ignore = "needs local signaling server + redis"]
async fn e2e_pairing_through_signaling_server() -> anyhow::Result<()> {
    // ── Initiator (A): local init + register mailbox ──
    let init = connection_init_local();
    let (status, init_resp) = http_post(
        "/connection/init",
        json!({"rendezvous_id_b64": init.rendezvous_id}),
    )
    .await?;
    anyhow::ensure!(status == 200, "init status {status}");
    let mailbox_a = init_resp["mailbox_id"].as_str().unwrap().to_string();
    println!("initiator mailbox: {mailbox_a}");

    // ── Responder (B): derive keys from link secret, join ──
    let keys_b = connection_derive_keys(init.secret.clone())?;
    let (status, join_resp) =
        http_post("/connection/join", json!({"token_b64": init.rendezvous_id})).await?;
    anyhow::ensure!(status == 200, "join status {status}");
    let mailbox_b = join_resp["mailbox_id"].as_str().unwrap().to_string();
    println!("responder mailbox: {mailbox_b}");

    // ── B sends encrypted hello, then sets up its WebRTC session ──
    send_signal(
        &mailbox_b,
        &keys_b.k_sig,
        json!({"type": "connect_request", "note": "Peer wants to connect"}),
    )
    .await?;
    create_session(mailbox_b.clone(), vec![]).await?;

    // ── A: sees hello, accepts, creates session + offer, sends it ──
    let mut seen_a = HashSet::new();
    let mut seen_b = HashSet::new();
    let hello = recv_signals(&mailbox_a, &init.k_sig, &mut seen_a).await?;
    anyhow::ensure!(
        hello.iter().any(|m| m["type"] == "connect_request"),
        "initiator did not receive hello"
    );
    create_session(mailbox_a.clone(), vec![]).await?;
    let offer = create_offer(mailbox_a.clone()).await?;
    println!("offer sdp bytes: {}", offer.sdp.len());
    send_signal(
        &mailbox_a,
        &init.k_sig,
        json!({"type": "offer", "data": {"sdp": offer.sdp, "type": offer.kind}}),
    )
    .await?;

    // ── Both peers run the Dart-style 100ms poll loop ──
    let mut a_connected = false;
    let mut b_connected = false;
    let deadline = tokio::time::Instant::now() + std::time::Duration::from_secs(12);

    while tokio::time::Instant::now() < deadline && !(a_connected && b_connected) {
        // B: handle incoming signaling (offer/ice)
        for msg in recv_signals(&mailbox_b, &keys_b.k_sig, &mut seen_b).await? {
            match msg["type"].as_str().unwrap_or("") {
                "offer" => {
                    let answer = create_answer(
                        mailbox_b.clone(),
                        SessionDescriptionDto {
                            kind: msg["data"]["type"].as_str().unwrap().to_string(),
                            sdp: msg["data"]["sdp"].as_str().unwrap().to_string(),
                        },
                    )
                    .await?;
                    println!("answer sdp bytes: {}", answer.sdp.len());
                    send_signal(
                        &mailbox_b,
                        &keys_b.k_sig,
                        json!({"type": "answer", "data": {"sdp": answer.sdp, "type": answer.kind}}),
                    )
                    .await?;
                }
                "ice" => {
                    add_ice_candidate(
                        mailbox_b.clone(),
                        IceCandidateDto {
                            candidate: msg["data"]["candidate"].as_str().unwrap().to_string(),
                            sdp_mid: msg["data"]["sdpMid"].as_str().map(String::from),
                            sdp_mline_index: msg["data"]["sdpMLineIndex"]
                                .as_u64()
                                .map(|v| v as u16),
                        },
                    )
                    .await?;
                }
                other => println!("[B] ignoring signal type {other}"),
            }
        }

        // A: handle incoming signaling (answer/ice)
        for msg in recv_signals(&mailbox_a, &init.k_sig, &mut seen_a).await? {
            match msg["type"].as_str().unwrap_or("") {
                "answer" => {
                    set_remote_answer(
                        mailbox_a.clone(),
                        SessionDescriptionDto {
                            kind: msg["data"]["type"].as_str().unwrap().to_string(),
                            sdp: msg["data"]["sdp"].as_str().unwrap().to_string(),
                        },
                    )
                    .await?;
                    println!("[A] remote answer applied");
                }
                "ice" => {
                    add_ice_candidate(
                        mailbox_a.clone(),
                        IceCandidateDto {
                            candidate: msg["data"]["candidate"].as_str().unwrap().to_string(),
                            sdp_mid: msg["data"]["sdpMid"].as_str().map(String::from),
                            sdp_mline_index: msg["data"]["sdpMLineIndex"]
                                .as_u64()
                                .map(|v| v as u16),
                        },
                    )
                    .await?;
                }
                other => println!("[A] ignoring signal type {other}"),
            }
        }

        poll_peer(
            &mailbox_a,
            &mailbox_a,
            &init.k_sig,
            &mailbox_b,
            &mut a_connected,
        )
        .await?;
        poll_peer(
            &mailbox_b,
            &mailbox_b,
            &keys_b.k_sig,
            &mailbox_a,
            &mut b_connected,
        )
        .await?;

        tokio::time::sleep(std::time::Duration::from_millis(100)).await;
    }

    close_session(mailbox_a.clone()).await?;
    close_session(mailbox_b.clone()).await?;

    assert!(a_connected, "initiator never connected within 12s");
    assert!(b_connected, "responder never connected within 12s");
    Ok(())
}
