use once_cell::sync::Lazy;
use std::sync::Mutex;

static BUFFER: Lazy<Mutex<Vec<String>>> = Lazy::new(|| Mutex::new(Vec::new()));

#[flutter_rust_bridge::frb(sync)]
pub fn greet(name: String) -> String {
    if name == "__consume__" {
        let mut buf = BUFFER.lock().unwrap();
        if buf.is_empty() {
            return String::new();
        }
        return buf.remove(0);
    }

    if name == "__list__" {
        let buf = BUFFER.lock().unwrap();
        return buf.join("|||");
    }

    let greeting = format!("{name}!");
    let mut buf = BUFFER.lock().unwrap();
    buf.insert(0, greeting.clone());
    if buf.len() > 10 {
        buf.truncate(10);
    }
    greeting
}

#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
}
