use std::{
    env::{self, var_os},
    path::{Path, PathBuf},
    sync::mpsc::Receiver,
};

use image::{RgbaImage, open};
use percent_encoding::percent_decode_str;
use serde::Deserialize;
use url::Url;
use xcb::{
    Connection as XcbConnection, Xid,
    randr::{GetMonitors, MonitorInfoBuf, Output},
    x::{Atom, InternAtom, ScreenBuf},
};
use zbus::{
    blocking::{Connection as ZBusConnection, Proxy},
    zvariant::Type,
};

use crate::{XCapError, error::XCapResult};

pub fn get_xcb_connection_and_index() -> XCapResult<(XcbConnection, i32)> {
    let display = env::var("DISPLAY").unwrap_or_else(|_| "DISPLAY:1".to_string());
    let (conn, idx) = XcbConnection::connect(Some(display.as_str()))
        .or_else(|_| XcbConnection::connect(None))
        .map_err(|e| XCapError::new(e.to_string()))?;
    Ok((conn, idx))
}

pub fn get_zbus_connection() -> XCapResult<ZBusConnection> {
    // RE:LINK PATCH: share one session connection. The portal derives the
    // Request object path from the unique name of the connection that made
    // the method call and addresses the Response signal to it; building the
    // request path from (and subscribing on) a different connection means
    // the response can never be observed, deadlocking the portal handshake.
    static CONNECTION: std::sync::OnceLock<ZBusConnection> = std::sync::OnceLock::new();
    if let Some(conn) = CONNECTION.get() {
        return Ok(conn.clone());
    }
    let conn = ZBusConnection::session().map_err(XCapError::ZbusError)?;
    Ok(CONNECTION.get_or_init(|| conn).clone())
}

pub fn wayland_detect() -> bool {
    let xdg_session_type = var_os("XDG_SESSION_TYPE")
        .unwrap_or_default()
        .to_string_lossy()
        .to_string();

    let wayland_display = var_os("WAYLAND_DISPLAY")
        .unwrap_or_default()
        .to_string_lossy()
        .to_string();

    xdg_session_type.eq("wayland") || wayland_display.to_lowercase().contains("wayland")
}

pub fn get_current_screen_buf() -> XCapResult<ScreenBuf> {
    let (conn, index) = get_xcb_connection_and_index()?;

    let setup = conn.get_setup();

    let screen = setup
        .roots()
        .nth(index as usize)
        .ok_or_else(|| XCapError::new("Not found screen"))?;

    Ok(screen.to_owned())
}

pub fn get_monitor_info_buf(output: Output) -> XCapResult<MonitorInfoBuf> {
    let (conn, _) = get_xcb_connection_and_index()?;

    let screen_buf = get_current_screen_buf()?;

    let get_monitors_cookie = conn.send_request(&GetMonitors {
        window: screen_buf.root(),
        get_active: true,
    });

    let get_monitors_reply = conn.wait_for_reply(get_monitors_cookie)?;

    let monitor_info_iterator = get_monitors_reply.monitors();

    for monitor_info in monitor_info_iterator {
        for &item in monitor_info.outputs() {
            if item == output {
                return Ok(monitor_info.to_owned());
            }
        }
    }
    Err(XCapError::new("Not found monitor"))
}

pub fn get_atom(name: &str) -> XCapResult<Atom> {
    let (conn, _) = get_xcb_connection_and_index()?;
    let atom_cookie = conn.send_request(&InternAtom {
        only_if_exists: true,
        name: name.as_bytes(),
    });
    let atom_reply = conn.wait_for_reply(atom_cookie)?;
    let atom = atom_reply.atom();

    if atom.is_none() {
        return Err(XCapError::new(format!("{name} not supported")));
    }

    Ok(atom)
}

pub(super) fn png_to_rgba_image<T>(
    filename: T,
    x: i32,
    y: i32,
    width: i32,
    height: i32,
) -> XCapResult<RgbaImage>
where
    T: AsRef<Path>,
{
    let mut dynamic_image = open(filename)?;
    dynamic_image = dynamic_image.crop(x as u32, y as u32, width as u32, height as u32);
    Ok(dynamic_image.to_rgba8())
}

/// uri 转换为 path
pub(super) fn safe_uri_to_path(uri: &str) -> XCapResult<PathBuf> {
    let url = Url::parse(uri)?;

    if url.scheme() != "file" {
        return Err(XCapError::new("Uri scheme is not file"));
    }

    // 获取已解码的路径
    let decoded_path = percent_decode_str(url.path())
        .decode_utf8_lossy()
        .to_string();

    let path = PathBuf::from(&decoded_path);

    Ok(path)
}

pub(super) fn get_zbus_portal_request(
    conn: &ZBusConnection,
    handle_token: &str,
) -> XCapResult<Proxy<'static>> {
    let unique_identifier = conn
        .unique_name()
        .ok_or(XCapError::new("Get DBus unique name failed"))?
        .trim_start_matches(':')
        .replace('.', "_");

    let path =
        format!("/org/freedesktop/portal/desktop/request/{unique_identifier}/{handle_token}");

    let request = Proxy::new(
        conn,
        "org.freedesktop.portal.Desktop",
        path,
        "org.freedesktop.portal.Request",
    )?;

    Ok(request)
}

pub(super) fn wait_zbus_response<T>(request: &Proxy<'static>) -> Receiver<XCapResult<T>>
where
    T: for<'de> Deserialize<'de> + Type + Send + Sync + 'static,
{
    let (sender, receiver) = std::sync::mpsc::channel();
    let (ready_sender, ready_receiver) = std::sync::mpsc::channel();

    let request = request.clone();
    std::thread::spawn(move || {
        // RE:LINK PATCH: the portal can emit Response within milliseconds of
        // the method call, and a signal emitted before the match rule is
        // installed is silently lost, deadlocking the recv below. Subscribe
        // first and only then unblock the caller to issue the method call.
        let stream = request.receive_signal("Response");
        let _ = ready_sender.send(());
        let response = match stream {
            Ok(mut stream) => wait_zbus_response_inner::<T>(&mut stream),
            Err(e) => Err(XCapError::ZbusError(e)),
        };
        sender
            .send(response)
            .map_err(|e| XCapError::new(format!("Failed to send zbus response: {e}")))
    });

    // Block until the subscription is active so the caller cannot race it.
    let _ = ready_receiver.recv();

    receiver
}

pub(super) fn wait_zbus_response_inner<T>(
    response: &mut zbus::blocking::proxy::SignalIterator<'_>,
) -> XCapResult<T>
where
    T: for<'de> Deserialize<'de> + Type,
{
    let message = response
        .next()
        .ok_or(XCapError::new("Failed get response"))?;

    let body = message.body();
    let (code, body): (u32, T) = body.deserialize()?;

    if code == 0 {
        return Ok(body);
    }

    if code == 1 {
        return Err(XCapError::new("Z-Bus canceled"));
    }

    Err(XCapError::new(format!("Response code is {code}")))
}
