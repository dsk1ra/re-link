fn main() {
    println!("cargo:rustc-check-cfg=cfg(frb_expand)");
}
