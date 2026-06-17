//! Temporary in-process pairing reproduction test.

use crate::api::webrtc::*;

async fn pump_events(
    from: &str,
    to: &str,
    connected: &mut bool,
    control_open: &mut bool,
) -> anyhow::Result<()> {
    let events = drain_events(from.to_string()).await?;
    for event in events {
        match event {
            WebRtcEvent::LocalIceCandidate { candidate } => {
                println!("[{from}] local candidate -> {to}: {}", candidate.candidate);
                add_ice_candidate(to.to_string(), candidate).await?;
            }
            WebRtcEvent::ConnectionStateChanged { state } => {
                println!("[{from}] connection state: {state}");
                if state == "connected" {
                    *connected = true;
                }
            }
            WebRtcEvent::DataChannelStateChanged { label, state } => {
                println!("[{from}] data channel {label}: {state}");
                if label == "control" && state == "open" {
                    *control_open = true;
                }
            }
            _ => {}
        }
    }
    Ok(())
}

#[tokio::test(flavor = "multi_thread")]
async fn pairing_handshake_completes() -> anyhow::Result<()> {
    create_session("peer_a".to_string(), vec![]).await?;
    create_session("peer_b".to_string(), vec![]).await?;

    let offer = create_offer("peer_a".to_string()).await?;
    println!("--- OFFER SDP ---\n{}\n-----------------", offer.sdp);

    let answer = create_answer("peer_b".to_string(), offer).await?;
    println!("--- ANSWER SDP ---\n{}\n------------------", answer.sdp);

    set_remote_answer("peer_a".to_string(), answer).await?;

    let mut a_connected = false;
    let mut b_connected = false;
    let mut a_control = false;
    let mut b_control = false;

    let deadline = tokio::time::Instant::now() + std::time::Duration::from_secs(15);
    while tokio::time::Instant::now() < deadline {
        pump_events("peer_a", "peer_b", &mut a_connected, &mut a_control).await?;
        pump_events("peer_b", "peer_a", &mut b_connected, &mut b_control).await?;
        if a_connected && b_connected && a_control && b_control {
            break;
        }
        tokio::time::sleep(std::time::Duration::from_millis(100)).await;
    }

    close_session("peer_a".to_string()).await?;
    close_session("peer_b".to_string()).await?;

    assert!(a_connected, "peer_a never reached connected state");
    assert!(b_connected, "peer_b never reached connected state");
    assert!(a_control, "peer_a control channel never opened");
    assert!(b_control, "peer_b control channel never opened");
    Ok(())
}
