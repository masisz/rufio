use magnus::{define_module, function, prelude::*, Error, RHash, Ruby, Value};
use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::path::Path;

/// ディレクトリエントリ情報
#[derive(Debug)]
struct DirEntry {
    name: String,
    is_dir: bool,
    size: u64,
    mtime: i64,
    executable: bool,
    hidden: bool,
}

/// ディレクトリをスキャンしてエントリを取得
fn scan_directory_impl(path: &str) -> Result<Vec<DirEntry>, std::io::Error> {
    let dir_path = Path::new(path);

    if !dir_path.is_dir() {
        return Err(std::io::Error::new(
            std::io::ErrorKind::NotFound,
            format!("Directory does not exist: {}", path),
        ));
    }

    let mut entries = Vec::new();

    for entry in fs::read_dir(dir_path)? {
        let entry = entry?;
        let metadata = entry.metadata()?;
        let file_name = entry.file_name();
        let name = file_name.to_string_lossy().to_string();

        // "." と ".." は除外
        if name == "." || name == ".." {
            continue;
        }

        let is_hidden = name.starts_with('.');
        let is_dir = metadata.is_dir();
        let size = metadata.len();

        // mtimeを取得
        let mtime = metadata
            .modified()
            .ok()
            .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
            .map(|d| d.as_secs() as i64)
            .unwrap_or(0);

        // 実行可能フラグ（Unixのみ）
        let executable = {
            #[cfg(unix)]
            {
                let permissions = metadata.permissions();
                permissions.mode() & 0o111 != 0
            }
            #[cfg(not(unix))]
            {
                false
            }
        };

        entries.push(DirEntry {
            name,
            is_dir,
            size,
            mtime,
            executable,
            hidden: is_hidden,
        });
    }

    Ok(entries)
}

/// Rubyから呼び出されるscan_directory関数
fn scan_directory(ruby: &Ruby, path: String) -> Result<Value, Error> {
    let entries = scan_directory_impl(&path)
        .map_err(|e| Error::new(ruby.exception_runtime_error(), e.to_string()))?;

    // Ruby配列を作成
    let ary = ruby.ary_new_capa(entries.len());

    for entry in entries {
        // Rubyハッシュを作成
        let hash = RHash::new();
        hash.aset(ruby.to_symbol("name"), entry.name)?;
        hash.aset(ruby.to_symbol("is_dir"), entry.is_dir)?;
        hash.aset(ruby.to_symbol("size"), entry.size)?;
        hash.aset(ruby.to_symbol("mtime"), entry.mtime)?;
        hash.aset(ruby.to_symbol("executable"), entry.executable)?;
        hash.aset(ruby.to_symbol("hidden"), entry.hidden)?;

        ary.push(hash)?;
    }

    Ok(ary.as_value())
}

/// 高速スキャン（エントリ数制限付き）
fn scan_directory_fast(ruby: &Ruby, path: String, max_entries: usize) -> Result<Value, Error> {
    let dir_path = Path::new(&path);

    if !dir_path.is_dir() {
        return Err(Error::new(
            ruby.exception_runtime_error(),
            format!("Directory does not exist: {}", path),
        ));
    }

    let ary = ruby.ary_new_capa(max_entries.min(100));
    let mut count = 0;

    for entry in fs::read_dir(dir_path)
        .map_err(|e| Error::new(ruby.exception_runtime_error(), e.to_string()))?
    {
        if count >= max_entries {
            break;
        }

        let entry = entry.map_err(|e| Error::new(ruby.exception_runtime_error(), e.to_string()))?;
        let metadata = entry
            .metadata()
            .map_err(|e| Error::new(ruby.exception_runtime_error(), e.to_string()))?;

        let file_name = entry.file_name();
        let name = file_name.to_string_lossy().to_string();

        if name == "." || name == ".." {
            continue;
        }

        let is_hidden = name.starts_with('.');
        let is_dir = metadata.is_dir();
        let size = metadata.len();

        let mtime = metadata
            .modified()
            .ok()
            .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
            .map(|d| d.as_secs() as i64)
            .unwrap_or(0);

        let executable = {
            #[cfg(unix)]
            {
                let permissions = metadata.permissions();
                permissions.mode() & 0o111 != 0
            }
            #[cfg(not(unix))]
            {
                false
            }
        };

        let hash = RHash::new();
        hash.aset(ruby.to_symbol("name"), name)?;
        hash.aset(ruby.to_symbol("is_dir"), is_dir)?;
        hash.aset(ruby.to_symbol("size"), size)?;
        hash.aset(ruby.to_symbol("mtime"), mtime)?;
        hash.aset(ruby.to_symbol("executable"), executable)?;
        hash.aset(ruby.to_symbol("hidden"), is_hidden)?;

        ary.push(hash)?;
        count += 1;
    }

    Ok(ary.as_value())
}

/// バージョン情報
fn get_version(_ruby: &Ruby) -> Result<String, Error> {
    Ok("1.0.0-magnus".to_string())
}

/// Ruby拡張の初期化
#[magnus::init]
fn init(ruby: &Ruby) -> Result<(), Error> {
    // Rufioモジュールを取得または作成
    let rufio_module = match ruby.class_object().const_get::<_, magnus::RModule>("Rufio") {
        Ok(module) => module,
        Err(_) => define_module("Rufio")?,
    };

    // NativeScannerMagnusクラスを定義
    let scanner_class = rufio_module.define_class("NativeScannerMagnus", ruby.class_object())?;

    // クラスメソッドを定義
    scanner_class.define_singleton_method("scan_directory", function!(scan_directory, 1))?;
    scanner_class.define_singleton_method("scan_directory_fast", function!(scan_directory_fast, 2))?;
    scanner_class.define_singleton_method("version", function!(get_version, 0))?;

    Ok(())
}
