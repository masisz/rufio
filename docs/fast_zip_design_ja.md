# FastZip 実装検討（rufio 1.3）

ブランチ: `v1.3.0`
ステータス: Phase 1〜5 実装済み（Pure Ruby の一覧・展開・作成、`z` キー、Zig エンジンの並列展開・圧縮、8 プラットフォームのバイナリ同梱）

「FastZip 開発構想メモ（Ruby × Zig ネイティブ拡張アーカイバ）」を rufio 1.3 の機能として取り込む前提で、既存コードとの整合と実装方針を整理する。

---

## 1. 結論

| 項目 | 構想メモ | 本検討での方針 |
|------|----------|----------------|
| 置き場所 | 独立Gem `fast_zip` | まず rufio 内の機能として実装。ABIが Ruby 非依存なので、後から Gem に切り出せる |
| Ruby との接続 | C拡張（`Init_fast_zip` + `rb_thread_call_without_gvl`） | **既存の流儀に合わせて Fiddle + Ruby ABI 非依存の C 関数** |
| GVL 解放 | 自前で `rb_thread_call_without_gvl` | Fiddle が既定で解放する（下記 2.3）。長時間処理は既存スキャナと同じ「ハンドル＋ポーリング」型にしてキャンセル可能にする |
| ネイティブ非搭載環境 | 記載なし | **Pure Ruby 実装を必須のフォールバック兼リファレンス**とする（Phase 1 で実装済み） |
| 最初のユーザー価値 | — | `.zip` をプレビューペインで一覧表示（`unzip -l` 相当）※実装済み |

### 1.1 決定事項（2026-10-31）
- C 拡張にはしない。既存の Zig 連携（Fiddle + Ruby ABI 非依存の C 関数）で実装する
- Pure Ruby 版は残す（ネイティブ非搭載環境のフォールバック兼、互換性の基準）
- 展開時の安全対策を入れる（4.2）
- ネイティブバイナリはビルド済みのものを Gem に同梱して配る（1.2 の `make dist` の 8 プラットフォーム）
- 操作は Files モードで選択後に `z`（すべて .zip なら展開、それ以外は圧縮）。暗号化エントリはスキップのまま
- 展開上限は現在の値（合計 16GiB / 10 万エントリ / 1MiB 超で 1000:1）で確定。対応方式は Stored と Deflate のみ

---

## 2. 現状調査（事実）

### 2.1 rufio のアーカイブ対応
- `FilePreview#determine_file_type` は `.zip` 等を `archive` と判定するが、実際はバイナリ判定が先に走り「Binary file / Cannot preview」と表示されていた。
- 圧縮・展開機能はない。

### 2.2 既存の Zig ネイティブ拡張（1.2.0 時点）
- ソース: `lib_zig/rufio_native/src/`（`main.zig` がエクスポート、`search.zig` がコンテンツ検索、`os.zig` が OS 差分の吸収）。Ruby ヘッダは include せず、`core_async_*` / `core_search_*` / `core_cache_*` という **Ruby ABI 非依存の C 関数**をエクスポートしている。
- Ruby 側: `lib/rufio/native_scanner_zig.rb` が `Fiddle::Importer` でロード。関数グループごとに `search_available?` のような判定があり、古いバイナリでも Ruby 実装に切り替わる。
- ビルド: Zig 0.17。`make -C lib_zig/rufio_native dist` で macOS（arm64/x86_64）・Linux（x86_64/aarch64、glibc 2.17+ と musl）・Windows（x64/arm64）の 8 種類をクロスコンパイルし、`lib/rufio/native/<platform>/` に同梱する。
- `test/test_native_platform_binaries.rb` が各バイナリの形式・CPU・必須エクスポート（`REQUIRED_EXPORTS`）を検証している。
- 1.2.0 で `rubyzip`（`>= 2.4, < 3.0`）が G モードの `.pptx` 読み取り用に依存関係に入った。ただし rubyzip 2.4 はファイル名を ASCII-8BIT で保持し、UTF-8 文字列で引けない（このブランチのテストで確認）。プレビュー・展開・作成は本実装を使い、rubyzip は相互運用テストの相手として使う。

### 2.3 Fiddle と GVL
- 本環境の fiddle 1.1.8 の `ext/fiddle/function.c` では、`need_gvl` の既定値が `Qfalse` で、その場合 `rb_thread_call_without_gvl` 経由で関数を呼ぶ。`Fiddle::Importer#extern` は `need_gvl` を指定しないので、**既存の Zig 関数呼び出しは GVL を解放して実行されている**。
- したがって構想メモの「GVL 解放のための C 拡張化」は、Fiddle 経由でも同じ効果が得られる。C 拡張にすると Ruby のマイナーバージョンごとにバイナリが必要になるデメリットの方が大きい。
- ただし Fiddle の GVL 解放ではキャンセル（unblock 関数）が指定できない。TUI から中断できるようにするため、展開・圧縮は既存スキャナと同じ非同期ハンドル方式を採る。

### 2.4 Ruby 標準 zlib でできること
- 構想メモの「zlib は ZIP 構造を扱えない」は正しいが、ZIP のコンテナ構造（EOCD / Central Directory / Local Header）は数百行の Ruby で扱える（Phase 1 で実装）。
- `Zlib::Inflate.new(-Zlib::MAX_WBITS)` / `Zlib::Deflate.new(level, -Zlib::MAX_WBITS)` で raw DEFLATE を扱え、`Zlib.crc32` もある。つまり **Pure Ruby + zlib だけで Store / Deflate の展開・作成まで実装できる**。ネイティブ実装は「速度のための加速器」という位置づけになる。

---

## 3. 実装内容（このブランチ）

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

### 3.5 Phase 2: 展開・作成（Pure Ruby）
- `Rufio::ZipExtractor`（`lib/rufio/zip_extractor.rb`）: Stored / Deflate の展開。安全対策は 4.2 をすべて実装。書き込み前に全エントリを検証し、危険なエントリが 1 件でもあれば何も書かない。進捗コールバックとキャンセルに対応。
- `Rufio::ZipWriter`（`lib/rufio/zip_writer.rb`）: ファイル・ディレクトリから ZIP を作成。UTF-8 名、縮まないファイルは Stored、ZIP64（4GiB 超・65535 件超）、シンボリックリンクと出力先自身はスキップ、一時ファイル経由で失敗時に残骸を残さない。
- テスト: `test/test_zip_extractor.rb` / `test/test_zip_writer.rb`。`zip` コマンド製（データディスクリプタ付きを含む）の展開、作成物の `unzip -t` 通過、rubyzip での読み取り、70,000 件での ZIP64 を確認。

## 4. 計画

| Phase | 内容 | 実装 | 備考 |
|-------|------|------|------|
| 2 | Store / Deflate の展開・作成 | Pure Ruby + zlib | **実装済み**。ネイティブ版のテストオラクルにする |
| 3 | Zig コア（展開・圧縮のデータ処理） | Zig + Fiddle | **実装済み**。同じテストを両実装で回す |
| 4 | 並列展開・並列圧縮 | Zig（ワーカースレッド） | **実装済み**。最大 16 スレッド、既定は CPU 数 |
| 5 | 配布・ベンチマーク | — | **実装済み**。`make dist` で 8 プラットフォーム分を同梱、`REQUIRED_EXPORTS` に `core_zip_*` を追加 |

### 4.1 TUI への組み込み（実装済み）
- Files モードで `Space` で選択してから `z`。選択がすべて `.zip` なら展開、それ以外は圧縮（`lib/rufio/archive_controller.rb`）
  - 展開: 確認ダイアログの後、各 ZIP を現在のディレクトリの `<名前>/` に展開（既にあれば `<名前> 2/` …）。失敗・キャンセル時は作った展開先を削除する
  - 圧縮: アーカイブ名を入力（空 Enter で 1 件なら `<名前>.zip`、複数なら `Archive.zip`）。同名ファイルがあればエラー通知
  - `..` は対象外
- 選択がなければ `z` は従来どおり zoxide（キー設定 `zoxide` を共用）
- 処理は `JobManager` のジョブとしてバックグラウンドスレッドで実行。ジョブ名に 5% 刻みで進捗を表示し、Jobs モードのキャンセルで中断できる。完了時に通知し、表示中のディレクトリなら一覧を再読み込みする
- 暗号化エントリはスキップ（決定事項）

### 4.2 安全性要件（実装済み。Ruby と Zig で共通）
- **Zip Slip**: `..`、絶対パス、Windows のドライブレター・`\` 区切りを含むエントリを拒否し、展開先ディレクトリ外に書かない
- **シンボリックリンク**: 外部属性で symlink を示すエントリは展開しない。展開先に既にあるシンボリックリンクも辿らない
- **ZIP 爆弾**: 展開後合計サイズ・圧縮率・エントリ数の上限。Central Directory 上のサイズを信用せず、実際に書いたバイト数で打ち切る。Local Header の範囲が重なるエントリ（重複参照型の爆弾）を拒否
- **CRC-32 検証**: 不一致なら展開したファイルを削除してエラー
- **既存ファイルの上書き**: 既定は拒否（`overwrite: true` で上書き）。UI では確認ダイアログを出す想定
- **ファイルモード**: 実行権限だけを引き継ぎ、setuid / setgid / sticky と他者書き込み権限は付けない
- 暗号化エントリ（ZipCrypto / AES）は初期は非対応としてスキップ

### 4.3 Zig エンジン（実装済み）
`lib_zig/rufio_native/src/zip.zig`。役割分担は次のとおりで、安全性の検証は Ruby 実装と共通にした。

| 処理 | 担当 |
|------|------|
| Central Directory の解析、パス正規化、上限・重複範囲・シンボリックリンクの検証、ディレクトリ作成 | Ruby |
| ZIP 内のデータ範囲を読み、伸長し、宣言サイズ超過で打ち切り、CRC-32 を検証して一時ファイルに書く | Zig（エントリ単位で並列） |
| 一時ファイルの rename、権限・日時の設定、失敗時の一時ファイル削除 | Ruby |
| ファイルを raw DEFLATE で一時ファイルへ圧縮し、CRC-32 とサイズを返す（1MiB 以上のファイルのみ） | Zig（ファイル単位で並列） |
| ローカルヘッダ・Central Directory・ZIP64 を書いてアーカイブを組み立てる | Ruby |

- エクスポート: `core_zip_extract_create` / `core_zip_deflate_create` / `core_zip_state` / `core_zip_progress` / `core_zip_status` / `core_zip_deflate_result` / `core_zip_cancel` / `core_zip_destroy`
- Ruby 側は `NativeScannerZigFFI.zip_available?` で関数グループの有無を判定し、ない場合（古いバイナリ）や `RUFIO_NATIVE_ZIP=0` では Pure Ruby を使う
- DEFLATE は Zig 標準ライブラリの `std.compress.flate`、CRC-32 は `std.hash.Crc32`。libdeflate は同梱していない
- ファイル操作は `os.zig` に追加（Linux は直接システムコール、macOS は libc、Windows は Win32。位置指定読み込み・排他作成・書き込み）
- `flate.Compress` は約 230KB あり初期化時にスタックへ載るため、ワーカースレッドのスタックは 4MB
- 1MiB 未満のファイルの圧縮は Ruby の zlib で行う。小さいファイルを Zig に渡すと、一時ファイルの作成・コピー・削除の分だけ遅くなった（2 万ファイルで 0.98 秒 → 5.26 秒）ため
- テスト: `test/test_zip_extractor.rb` / `test/test_zip_writer.rb` の全テストを `TestZipExtractorNative` / `TestZipWriterNative` で Zig 実装でも実行。Debug ビルド（安全チェック有効）でも全件通過を確認

### 4.4 計測（このクラウドコンテナ、4 CPU、Linux x86_64、ReleaseFast、各 3 回の最小値）

| データ | 処理 | Ruby | Zig | zip / unzip |
|--------|------|------|-----|-------------|
| 8 ファイル × 64MB のテキスト | 圧縮 | 15.36 秒 | 3.34 秒 | 20.20 秒 |
| 同上 | 展開 | 3.03 秒 | 0.94 秒 | 4.11 秒 |
| 2 万ファイル・計 79MB | 圧縮 | 0.93 秒 | 0.90 秒 | 0.30 秒 |
| 同上 | 展開 | 5.82 秒 | 5.00 秒 | 4.62 秒 |

- 圧縮後サイズは Zig の方がやや大きい（512MB → Ruby/zlib 67MB、Zig 71MB）。同じレベル指定でも実装が異なるため
- 小さいファイル大量の展開はファイル作成が律速で、計測ごとのばらつきが大きい（`sync` を挟まない計測では unzip 1.4〜1.8 秒、Ruby/Zig 3〜6 秒）。ファイルごとの Ruby 側処理（rename・chmod・utime）が残るため、unzip との差は縮め切れていない

## 5. 技術的な注意点（構想メモへのコメント）

- **libdeflate はストリーミング API を持たない**（バッファ全体を一度に処理する設計）。巨大エントリを扱うにはエントリ全体をメモリに載せるか mmap が必要。メモリ上限の設計とセットで検討する。ライセンスは MIT。
- **CRC-32**: 自前の SIMD 実装より、libdeflate の `libdeflate_crc32`（CPU 機能に応じた高速版を内部で選択）を使う方が保守コストが低い。
- **mmap**: POSIX と Windows で API が異なる。Windows 対応を続けるなら抽象化が必要（rufio は Windows 対応の修正を継続的に入れている）。
- **Zig のバージョン固定**: 既存 `build.zig` は `addExecutable(.{ .root_source_file = ... })` の書式。Zig はリリースごとにビルド API・標準ライブラリ（`std.compress.flate` 含む）が変わっているため、採用前に対象バージョンを決めて動作確認する必要がある（本検討では未確認）。
- **圧縮率**: 構想メモの通り DEFLATE は 32KB 窓・エントリ単位圧縮なので 7z には勝てない。比較軸は速度と OS 標準互換性に絞る。

---

## 6. 要判断事項
1. **独立 Gem 化のタイミング**: rufio 内で安定させてからか、`fast_zip` として切り出すか

## 7. 未確認事項
- Zig 版は Linux x86_64（このコンテナ）でのみ実行・計測した。macOS / Windows / aarch64 向けはクロスコンパイルとバイナリ形式・エクスポートの検証（`rake native:check`）までで、実機では動かしていない。特に Windows のファイル操作（`CreateFileW` / 位置指定 `ReadFile`）は未実行
- 計測は 1 環境・1 種類のデータのみ。CPU 数やストレージによって倍率は変わる
