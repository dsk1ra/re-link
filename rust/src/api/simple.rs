use once_cell::sync::Lazy;
use std::sync::Mutex;

static BUFFER: Lazy<Mutex<Vec<String>>> = Lazy::new(|| Mutex::new(Vec::new()));

#[flutter_rust_bridge::frb(sync)] // Synchronous mode for simplicity of the demo
pub fn greet(name: String) -> String {
    // Special commands:
    // "__consume__" -> remove and return the newest message, or empty string if none
    // "__list__" -> return all messages joined by "|||" (delimiter)

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

    // Produce: create the greeting and add it to the buffer (newest at front), but cap at 10
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
    // Default utilities - feel free to customize
    flutter_rust_bridge::setup_default_user_utils();
}
