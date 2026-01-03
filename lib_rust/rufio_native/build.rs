use std::process::Command;

fn main() {
    // Rubyのlibdirを取得
    let output = Command::new("ruby")
        .args(&["-e", "puts RbConfig::CONFIG['libdir']"])
        .output()
        .expect("Failed to execute ruby command");

    let lib_dir = String::from_utf8(output.stdout)
        .expect("Invalid UTF-8")
        .trim()
        .to_string();

    // Rubyのヘッダーディレクトリを取得
    let output = Command::new("ruby")
        .args(&["-e", "puts RbConfig::CONFIG['rubyhdrdir']"])
        .output()
        .expect("Failed to execute ruby command");

    let hdr_dir = String::from_utf8(output.stdout)
        .expect("Invalid UTF-8")
        .trim()
        .to_string();

    // archディレクトリも取得
    let output = Command::new("ruby")
        .args(&["-e", "puts RbConfig::CONFIG['rubyarchhdrdir']"])
        .output()
        .expect("Failed to execute ruby command");

    let arch_dir = String::from_utf8(output.stdout)
        .expect("Invalid UTF-8")
        .trim()
        .to_string();

    // リンカーに情報を渡す
    println!("cargo:rustc-link-search=native={}", lib_dir);
    println!("cargo:rustc-link-lib=dylib=ruby.3.4");
    println!("cargo:rerun-if-changed=build.rs");

    // デバッグ出力
    eprintln!("Ruby lib_dir: {}", lib_dir);
    eprintln!("Ruby hdr_dir: {}", hdr_dir);
    eprintln!("Ruby arch_dir: {}", arch_dir);
}
