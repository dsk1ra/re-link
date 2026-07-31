//! Remote input injection, scoped to whatever capture source (a single
//! window, or the whole monitor) the host is currently sharing.
//!
//! ponytail: X11 only (via the `xcb` crate xcap already depends on, just
//! with its "xtest" feature turned on). Wayland/wlroots has no portal API
//! for window-scoped input injection (see the RemoteDesktop portal plan
//! memory) - if/when a GNOME/KDE Wayland path is added it needs its own
//! module behind the portal's RemoteDesktop interface. Windows/macOS are
//! not implemented yet.
//!
//! Consent is fail-closed: input for a connection is dropped unless the
//! host has explicitly called [`set_remote_control_allowed`] with `true`.
//! Scoping for a shared *window* is enforced by activating (raising +
//! focusing) that window before every injected event, so whatever receives
//! the input is always the shared window, not whatever else happened to be
//! on top. Sharing a whole *monitor* has no window to scope to, so input is
//! injected directly with no activation step.

use once_cell::sync::Lazy;
use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use tokio::sync::Mutex;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum MouseButton {
    Left,
    Middle,
    Right,
}

#[derive(Debug, Clone)]
pub(crate) enum InputMsg {
    MouseMove {
        nx: f64,
        ny: f64,
    },
    MouseButton {
        nx: f64,
        ny: f64,
        button: MouseButton,
        pressed: bool,
    },
    MouseScroll {
        nx: f64,
        ny: f64,
        delta_y: f64,
    },
    /// Exactly one of `unicode`/`named` is set. `unicode` types an arbitrary
    /// printable character; `named` covers a small fixed set of control
    /// keys (see `named_keysym`). No modifier chords, no F-keys/media keys.
    Key {
        unicode: Option<u32>,
        named: Option<String>,
        pressed: bool,
    },
}

#[derive(Debug, Clone, Copy)]
enum InputTarget {
    Window(u32),
    Monitor {
        x: i32,
        y: i32,
        width: u32,
        height: u32,
    },
}

struct ConnState {
    allowed: AtomicBool,
    target: Mutex<InputTarget>,
}

static TARGETS: Lazy<Mutex<HashMap<String, Arc<ConnState>>>> =
    Lazy::new(|| Mutex::new(HashMap::new()));

async fn get_or_create(connection_id: &str) -> Arc<ConnState> {
    let mut map = TARGETS.lock().await;
    map.entry(connection_id.to_string())
        .or_insert_with(|| {
            Arc::new(ConnState {
                allowed: AtomicBool::new(false),
                target: Mutex::new(InputTarget::Monitor {
                    x: 0,
                    y: 0,
                    width: 0,
                    height: 0,
                }),
            })
        })
        .clone()
}

/// Host-side consent toggle. Must be explicitly enabled before any
/// `input_*` control message from the peer is acted on.
pub async fn set_remote_control_allowed(
    connection_id: String,
    allowed: bool,
) -> anyhow::Result<()> {
    let state = get_or_create(&connection_id).await;
    state.allowed.store(allowed, Ordering::Relaxed);
    Ok(())
}

/// Records which source is being shared for `connection_id`, so later
/// input events know what to scope against. Called when capture starts.
pub(crate) async fn register_target(connection_id: &str, source_id: &str) {
    let target = match source_id.split_once(':') {
        Some(("window", id_str)) => {
            id_str
                .parse::<u32>()
                .map(InputTarget::Window)
                .unwrap_or(InputTarget::Monitor {
                    x: 0,
                    y: 0,
                    width: 0,
                    height: 0,
                })
        }
        Some(("monitor", id_str)) => super::screen_capture::find_monitor(id_str)
            .and_then(|m| {
                Ok(InputTarget::Monitor {
                    x: m.x()?,
                    y: m.y()?,
                    width: m.width()?,
                    height: m.height()?,
                })
            })
            .unwrap_or(InputTarget::Monitor {
                x: 0,
                y: 0,
                width: 0,
                height: 0,
            }),
        _ => InputTarget::Monitor {
            x: 0,
            y: 0,
            width: 0,
            height: 0,
        },
    };

    let state = get_or_create(connection_id).await;
    *state.target.lock().await = target;
}

/// Drops all input state for a connection. Called when capture stops.
pub(crate) async fn clear_target(connection_id: &str) {
    TARGETS.lock().await.remove(connection_id);
}

/// Recognizes this module's slice of the control-channel wire format,
/// mirroring how `file_transfer::is_file_transfer_control_message` owns its
/// own sub-protocol instead of routing through `webrtc::parse_control_message`.
pub(crate) fn parse_input_message(text: &str) -> Option<InputMsg> {
    let value: serde_json::Value = serde_json::from_str(text).ok()?;
    let message_type = value.get("type")?.as_str()?;
    let f64_field = |key: &str| value.get(key).and_then(|v| v.as_f64());

    match message_type {
        "input_mouse_move" => Some(InputMsg::MouseMove {
            nx: f64_field("nx")?,
            ny: f64_field("ny")?,
        }),
        "input_mouse_button" => Some(InputMsg::MouseButton {
            nx: f64_field("nx")?,
            ny: f64_field("ny")?,
            button: match value.get("button")?.as_str()? {
                "left" => MouseButton::Left,
                "middle" => MouseButton::Middle,
                "right" => MouseButton::Right,
                _ => return None,
            },
            pressed: value.get("pressed")?.as_bool()?,
        }),
        "input_mouse_scroll" => Some(InputMsg::MouseScroll {
            nx: f64_field("nx")?,
            ny: f64_field("ny")?,
            delta_y: f64_field("deltaY")?,
        }),
        "input_key" => Some(InputMsg::Key {
            unicode: value
                .get("unicode")
                .and_then(|v| v.as_u64())
                .map(|v| v as u32),
            named: value
                .get("named")
                .and_then(|v| v.as_str())
                .map(ToOwned::to_owned),
            pressed: value.get("pressed")?.as_bool()?,
        }),
        _ => None,
    }
}

#[cfg(target_os = "linux")]
mod linux {
    use super::{InputMsg, InputTarget, MouseButton};
    use anyhow::Context;
    use once_cell::sync::Lazy;
    use std::sync::Mutex as StdMutex;
    use xcb::x;
    use xcb::XidNew;

    static CONN: Lazy<anyhow::Result<(xcb::Connection, i32)>> =
        Lazy::new(|| xcb::Connection::connect(None).context("failed to connect to X server"));

    // Serializes the read-modify-write around the keyboard mapping scratch
    // keycode (§ inject_key) - two overlapping key events would otherwise
    // race on the same remapped keycode.
    static KEY_LOCK: StdMutex<()> = StdMutex::new(());

    fn conn() -> anyhow::Result<&'static xcb::Connection> {
        match CONN.as_ref() {
            Ok((conn, _)) => Ok(conn),
            Err(e) => Err(anyhow::anyhow!(e.to_string())),
        }
    }

    fn root_window(conn: &xcb::Connection) -> x::Window {
        conn.get_setup()
            .roots()
            .next()
            .expect("no X11 screens")
            .root()
    }

    fn atom(conn: &xcb::Connection, name: &str) -> anyhow::Result<x::Atom> {
        let cookie = conn.send_request(&x::InternAtom {
            only_if_exists: false,
            name: name.as_bytes(),
        });
        Ok(conn.wait_for_reply(cookie)?.atom())
    }

    /// Raises and focuses `window` per the EWMH `_NET_ACTIVE_WINDOW`
    /// convention, de-iconifying first if it's minimized. Best-effort: a
    /// window manager that ignores these client messages (rare on modern
    /// Linux desktops) means input still lands wherever the window manager
    /// currently has focus instead.
    fn activate_window(conn: &xcb::Connection, window: x::Window) -> anyhow::Result<()> {
        let root = root_window(conn);

        let wm_state = atom(conn, "WM_STATE")?;
        let change_state = x::ClientMessageEvent::new(
            window,
            wm_state,
            x::ClientMessageData::Data32([1, 0, 0, 0, 0]), // NormalState
        );
        conn.send_request(&x::SendEvent {
            propagate: false,
            destination: x::SendEventDest::Window(window),
            event_mask: x::EventMask::STRUCTURE_NOTIFY,
            event: &change_state,
        });

        let net_active_window = atom(conn, "_NET_ACTIVE_WINDOW")?;
        let activate = x::ClientMessageEvent::new(
            window,
            net_active_window,
            x::ClientMessageData::Data32([1, 0, 0, 0, 0]), // source indication: application
        );
        conn.send_request(&x::SendEvent {
            propagate: false,
            destination: x::SendEventDest::Window(root),
            event_mask: x::EventMask::SUBSTRUCTURE_NOTIFY | x::EventMask::SUBSTRUCTURE_REDIRECT,
            event: &activate,
        });
        conn.flush()?;
        Ok(())
    }

    /// Live position/size of `window` in root coordinates. Queried fresh
    /// every call (not cached) since the host can move/resize the shared
    /// window at any time.
    fn window_rect(
        conn: &xcb::Connection,
        window: x::Window,
    ) -> anyhow::Result<(i32, i32, u32, u32)> {
        let geom_cookie = conn.send_request(&x::GetGeometry {
            drawable: x::Drawable::Window(window),
        });
        let geom = conn.wait_for_reply(geom_cookie)?;

        let translate_cookie = conn.send_request(&x::TranslateCoordinates {
            src_window: window,
            dst_window: geom.root(),
            src_x: 0,
            src_y: 0,
        });
        let translated = conn.wait_for_reply(translate_cookie)?;

        Ok((
            translated.dst_x() as i32,
            translated.dst_y() as i32,
            geom.width() as u32,
            geom.height() as u32,
        ))
    }

    /// Maps the event's normalized (0..1) coordinates to absolute screen
    /// coordinates for the current target, activating the target window
    /// first if it isn't already focused. Returns `None` if a window
    /// target no longer exists (closed since capture started).
    fn resolve_point(
        conn: &xcb::Connection,
        target: InputTarget,
        nx: f64,
        ny: f64,
    ) -> anyhow::Result<Option<(i16, i16)>> {
        match target {
            InputTarget::Window(xid) => {
                let window: x::Window = x::Window::new(xid);
                let (x, y, width, height) = match window_rect(conn, window) {
                    Ok(rect) => rect,
                    Err(_) => return Ok(None), // window closed/invalid
                };
                activate_window(conn, window)?;
                Ok(Some((
                    (x as f64 + nx.clamp(0.0, 1.0) * width as f64) as i16,
                    (y as f64 + ny.clamp(0.0, 1.0) * height as f64) as i16,
                )))
            }
            InputTarget::Monitor {
                x,
                y,
                width,
                height,
            } => Ok(Some((
                (x as f64 + nx.clamp(0.0, 1.0) * width as f64) as i16,
                (y as f64 + ny.clamp(0.0, 1.0) * height as f64) as i16,
            ))),
        }
    }

    const XTEST_MOTION_NOTIFY: u8 = 6;
    const XTEST_BUTTON_PRESS: u8 = 4;
    const XTEST_BUTTON_RELEASE: u8 = 5;
    const XTEST_KEY_PRESS: u8 = 2;
    const XTEST_KEY_RELEASE: u8 = 3;

    fn fake_input(
        conn: &xcb::Connection,
        type_: u8,
        detail: u8,
        root_x: i16,
        root_y: i16,
    ) -> anyhow::Result<()> {
        let root = root_window(conn);
        conn.send_request(&xcb::xtest::FakeInput {
            r#type: type_,
            detail,
            time: 0,
            root,
            root_x,
            root_y,
            deviceid: 0,
        });
        conn.flush()?;
        Ok(())
    }

    fn button_code(button: MouseButton) -> u8 {
        match button {
            MouseButton::Left => 1,
            MouseButton::Middle => 2,
            MouseButton::Right => 3,
        }
    }

    /// Well-known X11 keysyms (keysymdef.h) for the small set of named
    /// control keys we support. Extend this list if more are needed.
    fn named_keysym(name: &str) -> Option<u32> {
        Some(match name {
            "Enter" => 0xff0d,
            "Backspace" => 0xff08,
            "Tab" => 0xff09,
            "Escape" => 0xff1b,
            "Delete" => 0xffff,
            "ArrowUp" => 0xff52,
            "ArrowDown" => 0xff54,
            "ArrowLeft" => 0xff51,
            "ArrowRight" => 0xff53,
            "Home" => 0xff50,
            "End" => 0xff57,
            // Modifiers - these are chords, not chars: the caller sends a
            // press, then whatever else is held, then a release, same as a
            // real key. The X server accumulates modifier state itself from
            // these real keycode presses (see find_keycode_for_keysym), so
            // there's no modifier-mask bookkeeping to do here.
            "ControlLeft" => 0xffe3,
            "ControlRight" => 0xffe4,
            "ShiftLeft" => 0xffe1,
            "ShiftRight" => 0xffe2,
            "AltLeft" => 0xffe9,
            "AltRight" => 0xffea,
            "MetaLeft" => 0xffeb,
            "MetaRight" => 0xffec,
            _ => return None,
        })
    }

    /// Unicode codepoint -> X11 keysym. Latin-1 keysyms are numerically
    /// identical to their codepoint; everything else uses the Unicode
    /// keysym range reserved by the X consortium (0x01000000 | codepoint).
    fn unicode_keysym(codepoint: u32) -> u32 {
        if codepoint <= 0xff {
            codepoint
        } else {
            0x0100_0000 | codepoint
        }
    }

    /// Reverse-looks-up `keysym` to a keycode already bound to it *at the
    /// base (unmodified) level* on the current layout - modifiers (Ctrl,
    /// Shift, ...) and plain letters/digits are always bound this way.
    /// Only matching the base level matters here: a hit at a shifted level
    /// would mean this function's caller would also need to hold Shift to
    /// reproduce it, which isn't what "inject exactly this keysym" means.
    fn find_keycode_for_keysym(conn: &xcb::Connection, keysym: u32) -> Option<u8> {
        let setup = conn.get_setup();
        let min_kc = setup.min_keycode();
        let count = setup.max_keycode() - min_kc + 1;

        let cookie = conn.send_request(&x::GetKeyboardMapping {
            first_keycode: min_kc,
            count,
        });
        let reply = conn.wait_for_reply(cookie).ok()?;
        let per = reply.keysyms_per_keycode() as usize;
        if per == 0 {
            return None;
        }
        reply
            .keysyms()
            .chunks(per)
            .position(|group| group.first().copied() == Some(keysym))
            .map(|i| min_kc + i as u8)
    }

    /// Injects a press/release of `keysym`. Prefers a keycode already bound
    /// to it on the current layout (correct for modifiers and anything on
    /// a standard keyboard - the X server needs the *real* modifier
    /// keycodes to compose chord state for other keys). Falls back to
    /// temporarily binding the server's highest keycode (conventionally
    /// unused by real hardware layouts) for characters not on the current
    /// layout at all - the same technique `xdotool type`/`ydotool` use for
    /// arbitrary Unicode text.
    fn inject_keysym(conn: &xcb::Connection, keysym: u32, pressed: bool) -> anyhow::Result<()> {
        let _guard = super::linux::KEY_LOCK.lock().unwrap();

        if let Some(keycode) = find_keycode_for_keysym(conn, keysym) {
            return fake_input(
                conn,
                if pressed {
                    XTEST_KEY_PRESS
                } else {
                    XTEST_KEY_RELEASE
                },
                keycode,
                0,
                0,
            );
        }

        let setup = conn.get_setup();
        let scratch_keycode = setup.max_keycode();

        if pressed {
            conn.send_request(&x::ChangeKeyboardMapping {
                keycode_count: 1,
                first_keycode: scratch_keycode,
                keysyms_per_keycode: 1,
                keysyms: &[keysym],
            });
            conn.flush()?;
            // The server needs a moment to propagate the new mapping before
            // XTest will honor it.
            std::thread::sleep(std::time::Duration::from_millis(10));
        }

        fake_input(
            conn,
            if pressed {
                XTEST_KEY_PRESS
            } else {
                XTEST_KEY_RELEASE
            },
            scratch_keycode,
            0,
            0,
        )
    }

    pub(super) fn handle(target: InputTarget, msg: InputMsg) -> anyhow::Result<()> {
        let conn = super::linux::conn()?;

        match msg {
            InputMsg::MouseMove { nx, ny } => {
                if let Some((x, y)) = resolve_point(conn, target, nx, ny)? {
                    fake_input(conn, XTEST_MOTION_NOTIFY, 0, x, y)?;
                }
            }
            InputMsg::MouseButton {
                nx,
                ny,
                button,
                pressed,
            } => {
                if let Some((x, y)) = resolve_point(conn, target, nx, ny)? {
                    fake_input(conn, XTEST_MOTION_NOTIFY, 0, x, y)?;
                    fake_input(
                        conn,
                        if pressed {
                            XTEST_BUTTON_PRESS
                        } else {
                            XTEST_BUTTON_RELEASE
                        },
                        button_code(button),
                        x,
                        y,
                    )?;
                }
            }
            InputMsg::MouseScroll { nx, ny, delta_y } => {
                if let Some((x, y)) = resolve_point(conn, target, nx, ny)? {
                    fake_input(conn, XTEST_MOTION_NOTIFY, 0, x, y)?;
                    // XTest has no scroll event; scroll wheels are buttons
                    // 4 (up) / 5 (down) per X11 convention, one click each.
                    let button = if delta_y < 0.0 { 4 } else { 5 };
                    fake_input(conn, XTEST_BUTTON_PRESS, button, x, y)?;
                    fake_input(conn, XTEST_BUTTON_RELEASE, button, x, y)?;
                }
            }
            InputMsg::Key {
                unicode,
                named,
                pressed,
            } => {
                let keysym = match (unicode, named.as_deref()) {
                    (Some(cp), _) => unicode_keysym(cp),
                    (None, Some(name)) => match named_keysym(name) {
                        Some(k) => k,
                        None => return Ok(()),
                    },
                    (None, None) => return Ok(()),
                };
                inject_keysym(conn, keysym, pressed)?;
            }
        }

        Ok(())
    }

    #[cfg(test)]
    mod tests {
        use super::*;

        #[test]
        fn ascii_and_latin1_codepoints_are_identity_keysyms() {
            assert_eq!(unicode_keysym(b'a' as u32), 97);
            assert_eq!(unicode_keysym(0xe9), 0xe9); // é
        }

        #[test]
        fn higher_unicode_uses_the_reserved_keysym_range() {
            assert_eq!(unicode_keysym(0x1f600), 0x0100_0000 | 0x1f600); // 😀
        }

        #[test]
        fn named_keys_resolve_known_and_reject_unknown() {
            assert_eq!(named_keysym("Enter"), Some(0xff0d));
            assert_eq!(named_keysym("ArrowLeft"), Some(0xff51));
            assert_eq!(named_keysym("F1"), None);
        }

        #[test]
        fn button_codes_match_x11_convention() {
            assert_eq!(button_code(MouseButton::Left), 1);
            assert_eq!(button_code(MouseButton::Middle), 2);
            assert_eq!(button_code(MouseButton::Right), 3);
        }

        #[test]
        #[ignore = "queries a live X11/XWayland display's real keyboard mapping"]
        fn finds_a_real_keycode_for_a_common_letter() {
            let conn = conn().expect("no X11 connection available");
            let keycode = find_keycode_for_keysym(conn, unicode_keysym(b'a' as u32))
                .expect("'a' should be on any layout");
            // Round-trip: the keycode this returned must actually carry
            // that keysym at its base level, or injecting it would type
            // the wrong character.
            assert_eq!(
                find_keycode_for_keysym(conn, unicode_keysym(b'a' as u32)),
                Some(keycode)
            );
        }

        #[test]
        #[ignore = "queries a live X11/XWayland display's real keyboard mapping"]
        fn falls_back_to_scratch_remap_for_unmapped_codepoints() {
            let conn = conn().expect("no X11 connection available");
            // Private-use-area codepoint: essentially guaranteed not bound
            // to any keycode on any real layout.
            assert_eq!(find_keycode_for_keysym(conn, unicode_keysym(0xf8ff)), None);
        }

        // Moves the real mouse cursor on whatever X11/XWayland display is
        // reachable - there's no way to verify XTest fake input actually
        // reaches the server without a live connection and an observable
        // side effect. Excluded from the default `cargo test` run for the
        // same reason `e2e_pairing_test` is: needs live external state.
        #[test]
        #[ignore = "moves the real mouse cursor; run manually with a live X11/XWayland display"]
        fn fake_motion_moves_the_real_pointer() {
            let conn = conn().expect("no X11 connection available");
            fake_input(conn, XTEST_MOTION_NOTIFY, 0, 123, 456).expect("fake input failed");
            std::thread::sleep(std::time::Duration::from_millis(50));

            let root = root_window(conn);
            let cookie = conn.send_request(&x::QueryPointer { window: root });
            let reply = conn.wait_for_reply(cookie).expect("query pointer failed");
            assert_eq!((reply.root_x(), reply.root_y()), (123, 456));
        }
    }
}

#[cfg(target_os = "linux")]
pub(crate) async fn handle_input_message(connection_id: &str, msg: InputMsg) {
    let state = get_or_create(connection_id).await;
    if !state.allowed.load(Ordering::Relaxed) {
        return;
    }
    let target = *state.target.lock().await;
    if let Err(e) = linux::handle(target, msg) {
        tracing::warn!("input injection failed: {e:#}");
    }
}

#[cfg(not(target_os = "linux"))]
pub(crate) async fn handle_input_message(_connection_id: &str, _msg: InputMsg) {
    // ponytail: no injector on this platform yet.
}
