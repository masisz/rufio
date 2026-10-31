# FastZip 実装検討（rufio 1.3）

ブランチ: `v1.3.0`
ステータス: 検討中（Phase 1 のみ実装済み）

「FastZip 開発構想メモ（Ruby × Zig ネイティブ拡張アーカイバ）」を rufio 1.3 の機能として取り込む前提で、既存コードとの整合と実装方針を整理する。

---

## 1. 結論（提案）

| 項目 | 構想メモ | 本検討での提案 |
|------|----------|----------------|
| 置き場所 | 独立Gem `fast_zip` | まず rufio 内の機能として実装。ABIが Ruby 非依存なので、後から Gem に切り出せる |
| Ruby との接続 | C拡張（`Init_fast_zip` + `rb_thread_call_without_gvl`） | **既存の流儀に合わせて Fiddle + Ruby ABI 非依存の C 関数** |
| GVL 解放 | 自前で `rb_thread_call_without_gvl` | Fiddle が既定で解放する（下記 2.3）。長時間処理は既存スキャナと同じ「ハンドル＋ポーリング」型にしてキャンセル可能にする |
| ネイティブ非搭載環境 | 記載なし | **Pure Ruby 実装を必須のフォールバック兼リファレンス**とする（Phase 1 で実装済み） |
| 最初のユーザー価値 | — | `.zip` をプレビューペインで一覧表示（`unzip -l` 相当）※実装済み |

---

## 2. 現状調査（事実）

### 2.1 rufio のアーカイブ対応
- `FilePreview#determine_file_type` は `.zip` 等を `archive` と判定するが、実際はバイナリ判定が先に走り「Binary file / Cannot preview」と表示されていた。
- 圧縮・展開機能はない。

### 2.2 既存の Zig ネイティブ拡張
- ソース: `lib_zig/rufio_native/src/main.zig`。Ruby ヘッダを include せず、`core_async_*` という **Ruby ABI 非依存の C 関数**をエクスポートしている。
- Ruby 側: `lib/rufio/native_scanner_zig.rb` が `Fiddle::Importer` でロード。「ハンドル（u64）を返す → 非同期実行 → 10ms ポーリング → 結果取得 → destroy」の設計。
- 同梱バイナリ `lib/rufio/native/rufio_zig.bundle` は **Mach-O arm64 のみ**（`file` コマンドで確認）。Linux / Windows / Intel Mac では Zig 拡張は使われず Ruby 実装にフォールバックしている。
- `build.zig` は `linkSystemLibrary("ruby.3.4")` しているが、`main.zig` は Ruby API を使っていない。ZIP 用に作り直すなら Ruby へのリンクは不要にできる。
- `Makefile` は `librufio_zig.dylib` を出力し `.bundle` にコピーする macOS 前提の手順。

### 2.3 Fiddle と GVL
- 本環境の fiddle 1.1.8 の `ext/fiddle/function.c` では、`need_gvl` の既定値が `Qfalse` で、その場合 `rb_thread_call_without_gvl` 経由で関数を呼ぶ。`Fiddle::Importer#extern` は `need_gvl` を指定しないので、**既存の Zig 関数呼び出しは GVL を解放して実行されている**。
- したがって構想メモの「GVL 解放のための C 拡張化」は、Fiddle 経由でも同じ効果が得られる。C 拡張にすると Ruby のマイナーバージョンごとにバイナリが必要になるデメリットの方が大きい。
- ただし Fiddle の GVL 解放ではキャンセル（unblock 関数）が指定できない。TUI から中断できるようにするため、展開・圧縮は既存スキャナと同じ非同期ハンドル方式を採る。

### 2.4 Ruby 標準 zlib でできること
- 構想メモの「zlib は ZIP 構造を扱えない」は正しいが、ZIP のコンテナ構造（EOCD / Central Directory / Local Header）は数百行の Ruby で扱える（Phase 1 で実装）。
- `Zlib::Inflate.new(-Zlib::MAX_WBITS)` / `Zlib::Deflate.new(level, -Zlib::MAX_WBITS)` で raw DEFLATE を扱え、`Zlib.crc32` もある。つまり **Pure Ruby + zlib だけで Store / Deflate の展開・作成まで実装できる**。ネイティブ実装は「速度のための加速器」という位置づけになる。

---

## 3. Phase 1 実装内容（このブランチ）

### 3.1 `Rufio::ZipArchive`（`lib/rufio/zip_archive.rb`）
読み取り専用。ファイル本体は読まず、末尾と Central Directory だけを読む。

- EOCD の後方探索（末尾 22 + 65535 バイト）。コメント長が整合し、かつ指す先に Central Directory シグネチャがある候補のみ採用（コメント内の偽シグネチャ対策）
- ZIP64（ZIP64 EOCD Locator / ZIP64 EOCD / ZIP64 拡張フィールド 0x0001）
- ファイル名のエンコーディング: 汎用フラグ bit 11 → UTF-8、Info-ZIP Unicode Path 拡張（0x7075、CRC 一致時のみ）、UTF-8 として不正なら CP932（Windows 日本語環境で作られた ZIP）として解釈、それも失敗したら置換文字
- DOS 日時の変換、ディレクトリ・暗号化フラグの判定
- `limit:` で先頭 N 件だけ読む（プレビュー用。総数は EOCD から得る）
- 範囲外オフセット・切り詰められたファイルは `ZipArchive::FormatError`
- マルチディスク（分割）ZIP は非対応

### 3.2 プレビュー統合
- `FilePreview#preview_file` で拡張子 `.zip` または先頭が `PK\x03\x04` / `PK\x05\x06` のファイルを `type: "archive"` として一覧表示（最大 200 件、超過分は件数のみ）
- 壊れた ZIP は `Invalid ZIP archive: <理由>` をエラー表示
- `UIRenderer#extract_preview_lines` が `archive` を表示対象に追加

### 3.3 テスト（`test/test_zip_archive.rb`）
フィクスチャはテスト内の最小 ZIP ライタで生成し、外部コマンドに依存しない。加えて `zip` / `unzip` がある環境では `unzip -Z1` の一覧と完全一致することを確認する（ない環境では skip）。

### 3.4 計測（参考値）
環境: このクラウドコンテナ（Linux x86_64, Ruby 3.3.6）、`zip -qr` で作成した 20,001 エントリ / 3.2MB の ZIP。各 5 回平均。

| 処理 | 時間 |
|------|------|
| `ZipArchive.list`（全 20,001 件） | 176 ms |
| `ZipArchive.list(limit: 200)` | 1.9 ms |
| `FilePreview#preview_file`（200 件表示） | 1.9 ms |
| 参考: `unzip -l`（全件を標準出力へ、`time` の real） | 55 ms |

プレビュー用途では Pure Ruby で十分速い。ネイティブ化の効果が出るのは「全件走査」と「展開・圧縮（データ本体の処理）」である。

---

## 4. Phase 2 以降の計画

| Phase | 内容 | 実装 | 備考 |
|-------|------|------|------|
| 2 | Store / Deflate の展開・作成 | Pure Ruby + zlib | 機能を先に完成させ、ネイティブ版のテストオラクルにする |
| 3 | Zig コア（一覧・展開） | Zig + Fiddle | Ruby 実装と同じ結果を返すことを互換条件に、同じテストを両実装で回す |
| 4 | 並列展開・並列圧縮 | Zig（`std.Thread.Pool`） | ZIP はエントリ単位で独立して圧縮されているため分割しやすい |
| 5 | 配布・ベンチマーク | — | 下記「要判断事項」の配布方式次第 |

### 4.1 TUI への組み込み（案）
- 展開・圧縮は `JobManager` / Jobs モードのジョブとして実行し、進捗とキャンセルを既存 UI に載せる。
- 現状の `JobManager#add_job` は外部コマンド実行前提（`command:`）なので、Ruby / ネイティブ処理をジョブ化するためのインタフェース追加が必要。
- キー割り当ては未決定（既存キーとの衝突確認が必要）。

### 4.2 安全性要件（展開を実装する前に必須）
- **Zip Slip**: `..`、絶対パス、Windows のドライブレター・`\` 区切りを含むエントリを拒否し、展開先ディレクトリ外に書かない
- **シンボリックリンク**: 外部属性で symlink を示すエントリは既定で展開しない（リンク経由で展開先外へ書き込まれるのを防ぐ）
- **ZIP 爆弾**: 展開後合計サイズ・圧縮率・エントリ数の上限。Central Directory 上のサイズを信用せず、実際に書いたバイト数で打ち切る。Local Header の範囲が重なるエントリ（重複参照型の爆弾）を拒否
- **CRC-32 検証**: 不一致なら展開したファイルを削除してエラー
- **既存ファイルの上書き**: 既定は確認ダイアログ
- 暗号化エントリ（ZipCrypto / AES）は初期は非対応としてスキップ

### 4.3 Zig ABI 案（未ビルド・スケッチ）
既存 `core_async_*` と同じ形に揃える。**この環境では Zig を実行できなかったため、以下はコンパイル未確認の設計案である。**

```zig
// 一覧（同期・軽量）
export fn zip_open(path: [*:0]const u8) u64;            // 0 = 失敗
export fn zip_entry_count(h: u64) u64;
export fn zip_entry_name(h: u64, i: u64, buf: [*]u8, len: usize) usize;
export fn zip_entry_attrs(h: u64, i: u64, size: *u64, csize: *u64,
                          method: *u16, crc: *u32, dos_datetime: *u32) i32;
export fn zip_last_error(h: u64, buf: [*]u8, len: usize) usize;
export fn zip_close(h: u64) void;

// 展開（非同期・キャンセル可能）
export fn zip_extract_async(h: u64, dest: [*:0]const u8, threads: u32, flags: u32) i32;
export fn zip_get_state(h: u64) u8;                      // idle/running/done/cancelled/failed
export fn zip_get_progress(h: u64, done_bytes: *u64, total_bytes: *u64) void;
export fn zip_cancel(h: u64) void;
```

- ファイル名のエンコーディング変換は Ruby 側に残す（生バイト列を返す）。CP932 変換表を Zig に持ち込まないため。
- 安全性チェック（4.2）は Zig 側でも必ず実装し、Ruby 実装と同じテストケースで確認する。

---

## 5. 技術的な注意点（構想メモへのコメント）

- **libdeflate はストリーミング API を持たない**（バッファ全体を一度に処理する設計）。巨大エントリを扱うにはエントリ全体をメモリに載せるか mmap が必要。メモリ上限の設計とセットで検討する。ライセンスは MIT。
- **CRC-32**: 自前の SIMD 実装より、libdeflate の `libdeflate_crc32`（CPU 機能に応じた高速版を内部で選択）を使う方が保守コストが低い。
- **mmap**: POSIX と Windows で API が異なる。Windows 対応を続けるなら抽象化が必要（rufio は Windows 対応の修正を継続的に入れている）。
- **Zig のバージョン固定**: 既存 `build.zig` は `addExecutable(.{ .root_source_file = ... })` の書式。Zig はリリースごとにビルド API・標準ライブラリ（`std.compress.flate` 含む）が変わっているため、採用前に対象バージョンを決めて動作確認する必要がある（本検討では未確認）。
- **圧縮率**: 構想メモの通り DEFLATE は 32KB 窓・エントリ単位圧縮なので 7z には勝てない。比較軸は速度と OS 標準互換性に絞る。

---

## 6. 要判断事項

1. **ネイティブバイナリの配布方式**
   - (a) 現状どおりビルド済みバイナリを同梱（現状は macOS arm64 のみ）
   - (b) プラットフォーム別のビルド済み Gem を CI で作る
   - (c) `gem install` 時に Zig でビルド（利用者に Zig が必要）
2. **独立 Gem 化のタイミング**: rufio 内で安定させてからか、最初から `fast_zip` として切り出すか
3. **展開・圧縮のキー割り当てと UI**（プレビュー以外の操作をどこまで 1.3 に入れるか）
4. **対応範囲**: 暗号化 ZIP、Deflate64 / Zstd 等の非標準メソッドを扱うか

## 7. 未確認事項
- Zig ツールチェーンはこの環境で実行が許可されなかったため、Zig コードのビルド・計測は一切行っていない。
- 構想メモにある「libdeflate / SIMD による圧倒的高速化」の度合いは、本検討では計測していない。
