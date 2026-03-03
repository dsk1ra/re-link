pub mod provider;

#[cfg(windows)]
pub mod windows;

#[cfg(not(windows))]
pub mod stub;
