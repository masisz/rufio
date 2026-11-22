# 表プレビュー設計（CSV の行列表示 / hjkl セル移動 / y でコピー、将来の SQLite・Excel 対応を含む）

対象バージョン: 1.7.0 想定（1.6.0 時点のコードを調査）
ステータス: Phase 1・2・3 実装済み / Phase 4 は検討案

## 1. 目的とスコープ

当面の実装対象:

- `.csv` / `.tsv` をプレビューで**行列（グリッド）表示**する（CP932 の自動判定を含む）
- プレビューモード（`P`）で **`h` `j` `k` `l`** によりセルカーソルを移動する
- カーソル位置のセルを **`y`** でクリップボードへコピーする
- Files / Config モードの **`y`** は**ファイルパスをクリップボードへコピー**する

将来の実装対象（今回は「入る余地を作る」ところまで）:

- SQLite データベースのテーブルプレビュー
- Excel（`.xlsx`）のシートプレビュー

スコープ外: セルの編集、ソート、表内検索、範囲選択。

## 2. 現状の調査結果（事実）

| 項目 | 現状 | 参照 |
|---|---|---|
| プレビュー生成 | `FilePreview#preview_file` が `{type:, lines:, ...}` を返す。`.csv` は `determine_file_type` の `else` に落ちて `type: "text"` 扱い | `lib/rufio/file_preview.rb:24`, `:135` |
| 読み込み上限 | 先頭 64 KiB（`MAX_PREVIEW_BYTES`）、既定 50 行、1 行 500 文字 | `lib/rufio/file_preview.rb:6-8`, `:108` |
| 文字コード | バイト読み → UTF-8 強制 → 不正バイトは `?` に置換 | `lib/rufio/file_preview.rb:111-116` |
| 行抽出 | `extract_preview_lines` は `'text' / 'code' / 'archive'` のみ `lines` を返し、**未知の type は「プレビュー不可」表示**になる | `lib/rufio/ui_renderer.rb:233-243` |
| 描画 | `draw_file_preview_to_buffer` が折り返し（`wrap_preview_lines`）＋ bat ハイライトを幅ごとにキャッシュして描画。type 別の分岐点はこの 1 メソッドに集中 | `lib/rufio/ui_renderer.rb:319-` |
| プレビュー中のキー | `handle_preview_focus_key` が `j/k`（1 行）、`Ctrl+D/U`（20 行）、`ESC` のみ処理。**`h` / `l` / `y` / `0` / `$` は未使用** | `lib/rufio/navigation_controller.rb:222-237` |
| Files モードの `y` | `default_keybinds` に存在しない（未使用）。確認ダイアログの `y` は別入力ループ | `lib/rufio/config_loader.rb:47-89`, `lib/rufio/dialog_support.rb:26` |
| マウス | プレビュー中のホイールは `scroll_preview_up/down` を直接呼ぶ | `lib/rufio/terminal_ui.rb:698-703` |
| クリップボード | **実装が存在しない**（`pbcopy` / `xclip` / `wl-copy` / OSC 52 いずれの参照もなし） | `grep` 結果 0 件 |
| 依存 gem | `csv ~> 3.0` / `base64` / `roo ~> 2.10` は**すでに宣言済み**。`sqlite3` は無い | `rufio.gemspec` |
| Excel 読み取り | `Roo::Excelx#each_row_streaming` と `Roo::Utils.number_to_letter` を既に使用（全文検索用） | `lib/rufio/document_text_extractor.rb:56-65` |
| 幅計算 | `TextUtils.char_width` / `display_width` / `truncate_to_width` / `pad_string_to_width` が全角対応済み | `lib/rufio/text_utils.rb:25,42,51,87` |
| 選択状態 | `SelectionManager` が「選択元ディレクトリ＋名前」で複数選択を保持 | `lib/rufio/keybind_handler.rb:180-189` |
| 外部ツール連携 | rga / bat / zoxide は「あれば使う」方式で、`HealthChecker` が検出を担当 | `lib/rufio/health_checker.rb:18-139` |

制約: `NavigationController.new(listing, filter_manager)` の 2 引数呼び出しがテストから直接行われている（`test/test_navigation_mode_contracts.rb:31`）ため、引数追加はキーワード＋既定値にする。

## 3. 機能仕様

### 3.1 表示

分割ペイン・フルスクリーンの両方でグリッド表示する（セルカーソルはプレビューモード中のみ描画）。

```
 sales.csv [PREVIEW MODE]
 R3C2 price | hjkl: move  y: copy  ESC: back            copied (pbcopy)
     | A name       | B price | C stock |
   1 | apple        |     120 |      30 |
   2 | banana       |      80 |      12 |
   3 | みかん       |     150 |       8 |      <- C2 セルを反転表示
   4 | ...
     +-- 3 cols hidden (l to scroll) --  1000/4821 rows (truncated)  CP932
```

- 1 行目: 既存のファイル名ヘッダ（変更なし）
- 2 行目: セル番地・列名・操作ヒント・コピー結果
- 左に行番号ガター、ヘッダ行（既定で 1 行目）は縦スクロール中も固定表示
- カーソルセルは反転（`ColorHelper.color_to_selected_ansi`）
- 列幅に収まらないセルは `truncate_to_width` で切り詰め（末尾 `…`）
- 切り詰め（行数・列数・バイト数）と判定した文字コードを最下行に明示
- 複数シート／複数テーブルを持つ形式（Excel・SQLite）では最下行にシート名と件数を出す

### 3.2 キー

プレビューモード中かつ表プレビューのとき:

| キー | 動作 |
|---|---|
| `h` / `l` | 左 / 右のセルへ（`ConfigLoader.keybinds[:navigate_parent]` / `[:navigate_enter]` を参照） |
| `j` / `k` | 下 / 上のセルへ（`[:move_down]` / `[:move_up]` を参照） |
| 矢印キー | 同上 |
| `Ctrl+D` / `Ctrl+U` | 1 画面分の行移動 |
| `g` / `}` | 先頭行 / 最終行 |
| `0` / `$` | 行の先頭列 / 末尾列 |
| `y` | カーソルセルの**生の値**をクリップボードへ |
| `[` / `]` | 前 / 次のシート・テーブル（複数シート形式のみ、Phase 4） |
| `ESC` | ファイル一覧へ戻る |

Files / Config モード:

| キー | 動作 |
|---|---|
| `y` | カーソル位置のファイル／ディレクトリの**絶対パス**をクリップボードへ。現在ディレクトリに選択（`Space`）があるときは**選択された全パスを 1 行 1 件**でコピー |

表以外のファイルのプレビューは従来どおり（`j/k` スクロール、`h/l` は無反応）。

## 4. アーキテクチャ（拡張性を軸にした構成）

将来 SQLite・Excel・その他の形式を足すときに、**既存の描画メソッドやキー処理に分岐を増やさない**ことを設計目標にする。レイヤを 3 つに分ける。

```
┌─ 入力層: TableSource（形式ごとに 1 実装）────────────────────────┐
│  CsvTableSource / XlsxTableSource / SqliteTableSource / ...      │
│  役割: 「シート一覧」と「指定範囲の行」を返すだけ                │
└──────────────────────────────────────────────────────────────────┘
                 ↓ TableDocument（シート群）/ TableSheet（行の取得口）
┌─ 表示層: TablePreviewView ──────────────────────────────────────┐
│  TableLayout（列幅・可視列）＋ TableCursor（セル位置・スクロール）│
│  役割: どの形式でも共通のグリッド描画とキー処理                  │
└──────────────────────────────────────────────────────────────────┘
                 ↓ PreviewView プロトコル（draw / handle_key / status）
┌─ 統合層: PreviewRegistry ───────────────────────────────────────┐
│  拡張子・シグネチャ → プレビュー種別（text / archive / table / …）│
│  役割: 種別の追加を 1 箇所の登録で済ませる                       │
└──────────────────────────────────────────────────────────────────┘
```

### 4.1 `TableSource` インターフェース（拡張点その 1）

形式を追加するときに書くのはこれだけにする。

```ruby
module Rufio
  # 表として読める形式はこのインターフェースを満たす
  class TableSource
    # @return [Boolean] このソースが path を扱えるか（拡張子＋必要ならシグネチャ）
    def self.supports?(path) = raise NotImplementedError

    # @return [TableDocument] シート（Excel のシート / SQLite のテーブル / CSV は 1 枚）の一覧
    def open(path, limits:) = raise NotImplementedError
  end
end

TableDocument = Struct.new(:sheets, :source_label, keyword_init: true)

# 行は「必要になった分だけ」取りに行く
class TableSheet
  attr_reader :name, :columns, :row_count   # row_count は :unknown を許す
  def fetch_rows(offset, limit) = raise NotImplementedError  # => Array<Array<String>>
end
```

- **CSV**: 上限内を一括読みしてメモリ上の配列から `fetch_rows` を返す（最も単純な実装）
- **Excel**: `Roo::Excelx#each_row_streaming` で行を流し、取得済みブロックをキャッシュ（`document_text_extractor.rb:58` と同じ API）
- **SQLite**: `SELECT * FROM "<table>" LIMIT ? OFFSET ?` と `SELECT COUNT(*)` を発行

`fetch_rows(offset, limit)` を介すことで、巨大ファイルでも「見えている範囲＋前後 1 画面」しか読まない構造になる。CSV のみ先行実装する場合も、この口を通しておけば後から遅延読み込みの形式を足せる。

### 4.2 `TablePreviewView`（共通の表示・操作）

形式を問わず 1 実装。保持するのは `TableDocument`・現在シート・`TableCursor`・幅別の `TableLayout` キャッシュのみ。`TableSource` が何であるかを知らない。

### 4.3 `PreviewView` プロトコル（拡張点その 2）

現在、プレビュー中のキー処理は `handle_preview_focus_key` の `case` に、描画は `draw_file_preview_to_buffer` に集中している。ここを「ビューへの委譲」に変える。

```ruby
# プレビュー種別ごとのビューが満たす最小の約束
#   draw(screen, rect, focused:)   描画
#   handle_key(key) -> Boolean     プレビューフォーカス中のキー（扱わなければ false）
#   status_line -> String | nil    2 行目に出す情報
#   copy_target -> String | nil    y でコピーする文字列（nil ならコピー対象なし）
```

- `TextPreviewView`: 現在の折り返し＋ bat ハイライト＋スクロール（挙動は変更しない）
- `TablePreviewView`: グリッド＋セルカーソル
- 将来: `ImagePreviewView`（sixel/kitty）、`PdfPreviewView` などを足しても、`NavigationController` と `UIRenderer` は変更不要

`copy_target` をプロトコルに含めておくと、`y` の意味を「今見ているビューがコピーしたいものを渡す」に一般化でき、形式ごとに `y` の分岐を書かずに済む。

### 4.4 `PreviewRegistry`（拡張点その 3）

`FilePreview#determine_file_type` の `case` に手を入れずに種別を追加できるようにする。

```ruby
PreviewRegistry.register(:table, CsvTableSource)     # .csv .tsv .tab
PreviewRegistry.register(:table, XlsxTableSource)    # .xlsx .ods      （将来）
PreviewRegistry.register(:table, SqliteTableSource)  # .db .sqlite .sqlite3 + シグネチャ（将来）
```

`UIRenderer` 側も `type → ビュー` の対応表を 1 箇所に置き、`extract_preview_lines` / `draw_file_preview_to_buffer` の分岐増殖を止める。

### 4.5 新規ファイル

| ファイル | 責務 | Phase |
|---|---|---|
| `lib/rufio/table_source.rb` | インターフェース定義と共通の上限処理 | 1 |
| `lib/rufio/table_document.rb` | `TableDocument` / `TableSheet`（行取得口＋ブロックキャッシュ） | 1 |
| `lib/rufio/csv_table_source.rb` | CSV / TSV のパース | 1 |
| `lib/rufio/encoding_detector.rb` | BOM・UTF-8・CP932・EUC-JP の判定 | 1 |
| `lib/rufio/table_layout.rb` | 列幅・ガター・可視列、1 行分の文字列生成 | 1 |
| `lib/rufio/table_preview_view.rb` | グリッド描画とキー処理 | 1–2 |
| `lib/rufio/table_cursor.rb` | セル位置・行列スクロール・クランプ | 2 |
| `lib/rufio/clipboard.rb` | コピー実行（OS コマンド → OSC 52） | 3 |
| `lib/rufio/xlsx_table_source.rb` | Excel（`roo`） | 4 |
| `lib/rufio/sqlite_table_source.rb` | SQLite | 4 |

### 4.6 既存ファイルの変更

| ファイル | 変更 |
|---|---|
| `file_preview.rb` | `PreviewRegistry` 参照を追加し、表形式なら `type: 'table'`・`document:`・`lines:`（整形済みグリッド文字列、互換フォールバック）を返す |
| `ui_renderer.rb` | `extract_preview_lines` に `'table'` を追加（**必須**。無いと分割ペインが「プレビュー不可」になる）／type → ビューの対応表を導入し、グリッド描画をビューへ委譲／レイアウトを `@preview_cache[path][:table_layout][safe_width]` にキャッシュ |
| `navigation_controller.rb` | `focus_preview_pane` で該当ビューを生成、`unfocus_preview_pane` で破棄、`handle_preview_focus_key` はビューへ委譲（扱われなければ従来処理）。コンストラクタは `preview_factory:` のキーワード追加（既定値ありで後方互換） |
| `keybind_handler.rb` | `dispatch` に `:copy_cell`（Files モードではパスコピー）を追加 |
| `config_loader.rb` | `default_keybinds` に `copy_cell: 'y'`、`TABLE_PREVIEW` / `CLIPBOARD_COMMAND` 設定を追加 |
| `health_checker.rb` | クリップボード手段の検出、将来は `sqlite3` の検出も同じ枠組みで追加 |
| `help_menu.rb`, `info/help.md`, `info/keybindings.md`, `README*.md`, `docs/guide*.md`, `CHANGELOG.md` | ドキュメント追記 |

## 5. 文字コードの自動判定（CP932 を含む）

現状は UTF-8 強制＋不正バイトを `?` に置換するため、CP932 の CSV は全面的に化ける（`file_preview.rb:111-116`）。`EncodingDetector` を新設して Phase 1 で入れる。

判定順:

1. **BOM**
   - `EF BB BF` → UTF-8（BOM を除去）
   - `FF FE` / `FE FF` → UTF-16LE / UTF-16BE から UTF-8 へ変換（Excel の「Unicode テキスト」TSV がこれ）
2. BOM 無しで `valid_encoding?` が真 → UTF-8（ASCII のみもここに入る）
3. CP932 として `encode('UTF-8')` が例外なく通る → **CP932**
4. EUC-JP として通る → EUC-JP
5. いずれも失敗 → 従来どおり UTF-8＋置換（`?`）

補足:

- 3 と 4 は両方「通る」ことがある。日本語環境では CP932 の方が圧倒的に多いため CP932 を先に試す**ヒューリスティック**であり、誤判定は設定 `encoding:` で上書きできるようにする（`'auto'` 既定）
- **バイト上限での切断位置**: 64 KiB で機械的に切ると多バイト文字の途中で切れる。上限内の**最後の改行**までで切る（行指向データなので自然で、UTF-8・CP932 の双方で安全）
- 判定結果は画面最下行に表示し、化けたときにユーザーが原因を特定できるようにする
- クリップボードへは常に UTF-8 に正規化した値を渡す
- プレーンテキストプレビュー（`.txt` など）への適用は**今回は行わない**（`test_encoding_error_handling.rb` 等の既存の置換前提の挙動に影響するため、別途の変更として扱う）

## 6. パースと上限

### 6.1 区切り文字

- `.csv` → `,` / `.tsv` `.tab` → `\t`
- `.csv` で 1 行目に `;` が `,` より明らかに多い場合は `;` と推定（欧州式 CSV）。設定 `delimiter:` で固定可能

### 6.2 上限

| 項目 | 既定 | 理由 |
|---|---|---|
| バイト | 64 KiB（既存 `MAX_PREVIEW_BYTES` 流用、設定で 1 MiB まで） | 既存のプレビュー応答性方針 |
| 行 | 1,000（`fetch_rows` 方式なので将来引き上げ可） | 60 fps ループを阻害しない |
| 列 | 256 | 横スクロールが現実的な範囲 |
| 列幅 | 最小 3、最大 32 文字 | 極端なセルで表が崩れないように |
| Excel ファイルサイズ | 10 MiB 超は読み込まない（将来） | `roo` のメモリ使用量対策 |

切り詰めた行・列へはカーソルを移動できない（＝表示範囲とコピー可能範囲が一致する）。

### 6.3 壊れた CSV / 特殊なセル

- `CSV::MalformedCSVError` → `liberal_parsing: true` で再試行 → それでも失敗なら**従来のテキストプレビューにフォールバック**し、ヘッダに `(not parsed as table)` を付す
- セル内の改行・タブは表示時に半角スペース 1 個へ畳む。`y` は生の値（改行込み）をコピー
- 空行は空セル 1 つの行として表示（行番号を飛ばさない）
- ヘッダ行の有無は設定（既定 `header: true`）。自動推定は誤判定時の混乱が大きいため採用しない

## 7. 描画の詳細

- 列幅は読み込んだ行を `TextUtils.display_width` で走査して算出（コストが問題なら先頭 200 行に限定）
- パディングは `pad_string_to_width`、切り詰めは `truncate_to_width`。`wrap_preview_lines`（折り返し）は使わない
- 横スクロール: `col_offset` から可視幅に入る列を詰め、カーソルが可視範囲外になったら最小移動で調整
- 縦スクロール: 既存 `preview_scroll_offset` と同じ考え方。ヘッダ行は常に固定
- 狭い分割ペイン: まず行番号ガターを省略 → それでも入らなければ 1 列のみ → 幅 20 桁未満ならテキスト表示へフォールバック
- 非フォーカス時はセルカーソルを描画しない
- bat ハイライトは `type == 'code'` のみが対象（`ui_renderer.rb:353`）なので表プレビューには影響しない

## 8. クリップボード設計

```ruby
Rufio::Clipboard.copy(text) # => :pbcopy | :clip | :wl_copy | :xclip | :xsel | :osc52 | false
```

優先順:

1. 設定 `CLIPBOARD_COMMAND`（argv 配列）
2. OS 既定
   - macOS: `pbcopy`
   - Windows: `clip`（`Set-Clipboard` は起動が重いので第 2 候補）
   - Linux / BSD: `WAYLAND_DISPLAY` があれば `wl-copy`、`DISPLAY` があれば `xclip -selection clipboard` → `xsel --clipboard --input`
3. OSC 52 フォールバック（SSH 越しでも効く。端末側の対応に依存）

実装方針:

- 実行は `IO.popen(argv, 'w')` の **argv 配列**（シェル非経由。`file_opener.rb:123` と同じ方針、`SECURITY.md` に沿う）
- コマンド存在確認は 1 回だけ行い結果をメモ化
- OSC 52: `"\e]52;c;#{Base64.strict_encode64(text)}\a"` を STDOUT へ書いて `flush`。既存コードも制御シーケンスを `print` で直接出している（`terminal_ui.rb:142-183`）
  - `TMUX` 環境では DCS パススルー（`\ePtmux;` ＋ ESC を `\e\e` にエスケープ ＋ `\e\\`）が必要で、tmux 側の `set -g set-clipboard on` も必要
  - `TERM` が `screen*` の場合は DCS チャンク分割が必要
  - OSC 52 は**成否が取得できない**ため、未対応端末では無言で失敗する
- そのため「どの手段でコピーしたか」を 2 行目に約 1.5 秒表示（`copied (pbcopy)` / `copied (OSC52)`）。失敗時は `clipboard unavailable`
- サイズガード 100 KiB（複数パスのコピーや将来の範囲コピー向け）
- `base64` は依存済みのため新規依存は不要
- `rufio -c`（`HealthChecker`）に検出結果を追加

## 9. キーバインドの競合

- プレビューモード中の `h` / `l` / `y` / `0` / `$` は現在未使用（`navigation_controller.rb:222` の `case` に無い）→ **競合なし**
- Files モードの `y` も `default_keybinds` に無く未使用。確認ダイアログの `y` は別入力ループなので影響なし
- セル移動は `ConfigLoader.keybinds` の `move_up` / `move_down` / `navigate_parent` / `navigate_enter` を参照し、hjkl のユーザー変更に追従させる（既定値では挙動不変）
- `default_keybinds` に `copy_cell: 'y'` を追加すると `build_key_map`（`keybind_handler.rb:461`）経由で Files / Config モードでも `y` が dispatch される。`dispatch` で「表プレビュー中ならセル、それ以外はファイルパス」を振り分ける
- Job / Help / Log / 検索系モードは `handle_key` の前段で割り込むため `y` は届かない（Job モードでログパスをコピーする等は将来の拡張余地）
- マウスホイールは `preview_focused?` 時に `scroll_preview_up/down` を呼ぶ（`terminal_ui.rb:698-703`）。表モードでは行スクロールに割り当てる

## 10. 既存機能への影響と互換性

| 影響 | 対応 |
|---|---|
| `extract_preview_lines` が未知 type を「プレビュー不可」にする | `'table'` を分岐に追加（必須） |
| 検索画面のプレビュー（`FuzzyPreviewLoader`）は別経路 | `lines:` フォールバックで整形済みグリッド文字列が表示される（カーソル操作なし）。統合は Phase 4 |
| `NavigationController.new` の 2 引数呼び出し（テスト） | 追加引数はキーワード＋既定値 |
| `global_search` の CSV 読み取り | `DocumentTextExtractor` の別経路で無関係 |
| `type` 変更 | `.csv` を `text` と見なす既存テストがあれば更新 |

## 11. 将来の形式: 設計上の前提

### 11.1 Excel（`.xlsx`）

- `roo ~> 2.10` は**依存済み**で、`each_row_streaming` を既に使用している（`document_text_extractor.rb:58`）。新規依存なしで `XlsxTableSource` を書ける見込み
- シート = `TableSheet`。列見出しは `Roo::Utils.number_to_letter` で A / B / C を出せる
- 書式付き数値・日付はセルの**表示値**ではなく `roo` が返す値になるため、見た目が Excel と一致しないことがある（仕様として割り切る）
- `.xls`（旧バイナリ形式）は `roo` 2.x 単体では扱えないと認識しているが、実装前に要確認。`.ods` は `roo` が対応
- サイズガード（10 MiB 目安）が必要。`roo` はワークブックを展開するためメモリを食う

### 11.2 SQLite

- `sqlite3` gem は**依存に無く**、この環境に `sqlite3` コマンドも無い。選択肢は 3 つ:
  1. `sqlite3` gem を追加（ネイティブビルドが必要。`nokogiri` が既に native なので前例はある）
  2. **`sqlite3` CLI があれば使う**（rga / bat / zoxide と同じ「あれば使う」方式。`HealthChecker` に検出を追加）
  3. SQLite ファイルフォーマットを自前で読む（`lib_zig` の Zig コアに寄せる余地はあるが工数が大きい）
- 推奨は **2**。rufio の既存方針（インストール済みツールを追加設定なしで活用する）と一致し、依存を増やさない
- テーブル一覧は `sqlite_master`、各テーブルが `TableSheet` になる
- **読み取り専用で開く**こと（`-readonly` / `file:...?mode=ro`）と、発行するのは `SELECT ... LIMIT ?` と `COUNT(*)` のみに限ることを実装規約にする。テーブル名は識別子クォートでエスケープし、文字列連結で SQL を組まない
- 署名判定（先頭 16 バイト `SQLite format 3\0`）で拡張子に依存しない検出ができる

### 11.3 その他

同じ `TableSource` に乗せられる候補: `.ndjson` / `.jsonl`（1 行 1 レコード）、`.parquet`（外部ツール依存）、`rufio` 自身のジョブ一覧やログの表形式表示。

## 12. 実装フェーズ

| Phase | 内容 | 目安 |
|---|---|---|
| 1 | **実装済み**: `TableSource` / `TableDocument` / `CsvTableSource` / `EncodingDetector`（CP932 含む）/ `TableLayout`、`PreviewRegistry`、`FilePreview` の type 追加、分割＋フルスクリーンのグリッド表示（カーソルなし） | 中〜大 |
| 2 | **実装済み**: `PreviewView` プロトコルへの委譲、`TableCursor`、hjkl・ページ・`0`/`$`・`g`/`}`、2 行目のステータス、マウスホイール | 中 |
| 3 | **実装済み**: `Clipboard`、`y`（セル／ファイルパス）、コピー結果表示、`HealthChecker`、設定項目、ドキュメント | 小〜中 |
| 4 | `XlsxTableSource`、`SqliteTableSource`、シート切替（`[` / `]`）、`Y`（行コピー）、検索画面プレビューとの統合 | 中 |

Phase 1 単体でも「CSV が文字化けせず表で読める」価値が出る。Phase 3 の `y` は Files モードのパスコピーとセルコピーを同時に入れる。

## 13. テスト計画

新規:

- `test/test_encoding_detector.rb`: BOM（UTF-8 / UTF-16LE / UTF-16BE）、CP932、EUC-JP、判定不能時の置換、改行境界での切断
- `test/test_csv_table_source.rb`: 区切り推定、行/列/バイト上限、`MalformedCSVError` → `liberal_parsing` → テキストフォールバック、セル内改行の保持、`fetch_rows` の範囲指定
- `test/test_table_layout.rb`: 列幅算出（全角混在）、横スクロール時の可視列、狭幅フォールバック
- `test/test_table_cursor.rb`: hjkl のクランプ、ページ移動、カーソル追従スクロール
- `test/test_clipboard.rb`: `RbConfig` / `ENV` をスタブした手段選択、OSC 52 文字列（tmux ラップ含む）、コマンド不在時のフォールバック、**シェルを経由しないこと**
- `test/test_copy_path.rb`: Files モードの `y`（単一エントリ／複数選択／選択元が別ディレクトリのとき）
- `test/test_table_preview_integration.rb`: fixture CSV で `P` → `hjkl` → `y`（`Clipboard` スタブ）で期待セルが渡ること
- `test/test_preview_view_protocol.rb`: `TextPreviewView` / `TablePreviewView` が同じプロトコルを満たすこと（将来の形式追加時の回帰防止）

更新: `test_file_preview.rb` / `test_ui_renderer.rb`（`ui_test_harness.rb` でグリッド行を検証）/ `test_keybind_config.rb`（`copy_cell`）/ `test_preview_scroll.rb`（非表ファイルの挙動不変）/ `test_info_docs.rb`（`info/*.md` の整合）

fixture（`test/fixtures/`）: 全角混在、引用符、セル内改行、CP932、EUC-JP、UTF-16LE TSV、引用符が壊れた CSV、TSV。

## 14. 未決事項

1. **バイト上限**: 表プレビューだけ 64 KiB より広げるか（例: 256 KiB）。`fetch_rows` 方式なので後から広げられる
2. **`Y`（行コピー）** を入れるか（`y` はセル、`Y` は CSV 1 行）
3. **SQLite の読み取り手段**: `sqlite3` CLI 方式（推奨）か gem 追加か（Phase 4 着手時に決定）

## 15. 決定済み事項

- Files / Config モードの `y` は**ファイルパスのコピー**（選択があれば選択された全パスを 1 行 1 件）
- **CP932 自動判定は Phase 1 に含める**（BOM・UTF-8・CP932・EUC-JP の順で判定、設定で上書き可）
- プレビュー表示は `TableSource` / `PreviewView` / `PreviewRegistry` の 3 つの拡張点を設け、**SQLite・Excel を「ソースの追加」だけで足せる**構造にする
- ヘッダ行は既定で 1 行目を見出し扱い（`header: false` で無効化）
- **OSC 52 は既定で有効**にする（コマンドが見つからないときのフォールバック）。未対応端末では無言で失敗するため、
  「どの手段でコピーしたか」を必ず画面に出し、`rufio -c` でも確認できるようにする
- キーバインドのアクション名は `copy_cell` ではなく **`copy_to_clipboard`**（セルだけでなくパスもコピーするため）

## 16. Phase 1 実装記録

### 追加したファイル

| ファイル | 内容 |
|---|---|
| `lib/rufio/encoding_detector.rb` | BOM（UTF-8 / UTF-16LE / UTF-16BE）→ UTF-8 → CP932 → EUC-JP → 置換付き UTF-8 の判定。`read_text` は上限内の最後の改行で切る |
| `lib/rufio/table_document.rb` | `TableSheet`（`fetch_rows` / 列ラベル A..Z, AA..）、`MemoryTableSheet`、`TableDocument`（複数シート・状態表示） |
| `lib/rufio/table_source.rb` | 形式共通インターフェースと `Limits`、`ParseError` |
| `lib/rufio/csv_table_source.rb` | CSV / TSV のパース、区切り推定、上限適用 |
| `lib/rufio/table_layout.rb` | 列幅・ガター・可視列・行文字列の生成、`plain_lines` |
| `lib/rufio/preview_registry.rb` | 表ソースの登録表（`register_table_source` / `reset!`） |

変更: `file_preview.rb`（`type: 'table'` と `text_response` の切り出し、ParseError 時のフォールバック）、
`ui_renderer.rb`（`extract_preview_lines` に `'table'`、グリッド描画と幅別レイアウトキャッシュ）、
`config_loader.rb`（`TABLE_PREVIEW`）、`config.rb`（メッセージ 1 件）、`rufio.rb`（require）。

### 設計からの変更点

1. **壊れた CSV の復旧を 3 段にした**。`liberal_parsing: true` は**引用符の閉じ忘れを救わない**（`CSV::MalformedCSVError: Unclosed quoted field`）ことが実装中に判明した。
   バイト上限が引用符つきセルの途中に当たると必ずこれに当たるため、3 段目として「末尾に `"` を補って再パース」を追加した。
   結果として、テキストプレビューへのフォールバックは実際にはほとんど起きない
2. **表判定をバイナリ判定より前に置いた**。UTF-16 の CSV は NUL バイトが半分を占め、既存の `binary_file?` が 30% の閾値でバイナリと判定してしまうため
3. **最下行の情報をドキュメント側に持たせた**（`TableDocument#status_line`）。「`4 rows  4 cols  CP932  +1 hidden`」のように、
   行数・列数・判定した文字コード・切り詰め・収まらない列数を 1 行で出す。狭いペインでも収まるよう短い表記にした
4. **行番号ガターは幅が足りなければ落とす**。`TableLayout` が `幅 - ガター >= 区切り + 最小列幅` を満たさないときガターを 0 にする
5. **EUC-JP の判定にヒューリスティックを 1 つ足した**。EUC-JP のバイト列は CP932 としても「読めて」しまい半角カタカナの羅列になるため、
   CP932 で読んだ結果の半角カタカナ率が 50% を超える場合は EUC-JP を採用する

### 動作確認

- 新規テスト 4 ファイル（`test_encoding_detector.rb` / `test_csv_table_source.rb` / `test_table_layout.rb` / `test_table_preview.rb`）、計 79 ケース
- `rake test` 全体で新たな失敗はなし（既存の 13 件の失敗・エラーは変更前から発生している別件）
- tmux 上で実際に `bin/rufio` を起動して確認: 分割ペインとフルスクリーン（`P`）のグリッド表示、
  `j` でのスクロール時にヘッダ行が固定されること、CP932 の CSV が文字化けせず読めること、
  `.txt` のプレビューが従来どおりであること

### Phase 2 の着手点

- `handle_preview_focus_key`（`navigation_controller.rb:222`）をビューへの委譲に差し替える
- セルカーソルの描画は、`TableLayout#column_x` と `#format_cell` で該当セルだけを反転色で上書きする
  （行は `row_line` で描いてからカーソルセルを重ねる）
- 横スクロールは `visible_columns(col_offset)` に既に対応済み。`col_offset` を持つのは `TableCursor`

## 17. Phase 2 実装記録

### 追加したファイル

| ファイル | 内容 |
|---|---|
| `lib/rufio/preview_view.rb` | `PreviewView` プロトコル（`row_offset` / `reset` / `handle_key` / `scroll` / `page` / `status_line` / `copy_target` / `cursor` / `table?`）、種別を選ぶ `build`、`TextPreviewView` |
| `lib/rufio/table_preview_view.rb` | 表プレビューのビュー。キー → カーソル操作、セル番地の表示、`copy_target` |
| `lib/rufio/table_cursor.rb` | セル位置と縦横スクロール位置、クランプ、ページ送り、カーソル追従 |

変更: `navigation_controller.rb`（`focus_preview_pane` でビュー生成、`handle_preview_focus_key` はビューへ委譲、
`preview_scroll_offset` はビューに問い合わせ）、`keybind_handler.rb`（`preview_view` / `preview_cursor` の委譲）、
`ui_renderer.rb`（カーソルセルの反転描画、横スクロール、2 行目のステータス、表示行数の通知）、
`table_layout.rb`（`offset_for`）、`table_document.rb`（`row` / `cell`）、`preview_registry.rb`（パース結果の共有キャッシュ）。

### 設計からの変更点

1. **縦スクロールの責任を分けた**。「何行表示できるか」は描画側しか知らないため、`UIRenderer` が毎フレーム
   `TableCursor#visible_rows=` で伝え、カーソルはそれを使って `row_offset` を最小限ずらす。
   ページ送り（Ctrl+D/U）の移動量もこの値を使うので、ペインの高さに追従する
2. **横スクロール量の計算は `TableLayout#offset_for` に置いた**。列幅はレイアウトしか知らないため、
   カーソルは `column_offset` を持つだけで、どこまでずらすかはレイアウトが決める
3. **`preview_scroll_offset` をビューへの委譲にした**。既存の `UIRenderer` は従来どおり
   `keybind_handler.preview_scroll_offset` を読むだけでよく、テキストプレビューの挙動も変わらない
4. **パース結果を `PreviewRegistry.load_table` のキャッシュで共有した**。`FilePreview`（描画用）と
   `PreviewView.build`（カーソル用）が同じファイルを別々にパースしないようにするためで、キーはパス・更新時刻・
   サイズ・設定。`FuzzyPreviewLoader` が別スレッドから `preview_file` を呼ぶため `Monitor` で保護している
5. **`reset` をプロトコルに足した**。`reset_preview_scroll`（ファイル選択が変わったときに呼ばれる）が
   ビューの状態まで戻せず、既存テスト `test_reset_preview_scroll` が失敗したため。
   テキストは行位置を 0、表はカーソルとスクロール位置を先頭に戻す

### 動作確認

- 新規テスト 2 ファイル（`test_table_cursor.rb` 15 ケース / `test_preview_view.rb` 24 ケース）、
  `test_table_layout.rb` に `offset_for` の 5 ケース、`test_table_preview.rb` に描画 6 ケースを追加
- `rake test` 全体で新たな失敗はなし（既存の 13 件は変更前から発生している別件）
- tmux 上で `bin/rufio` を起動して確認:
  `hjkl` でのセル移動、カーソルセルが反転表示されること（`ESC[7m` が出力されること）、
  `}` で最終行へ飛ぶとヘッダ行を残して縦スクロールすること、`$` で右端の列まで横スクロールし
  最下行が `+2 hidden` になること、`0` で先頭列へ戻ること、`Ctrl+D` の移動量がペインの高さに追従すること、
  `ESC` で一覧に戻ること、テキストプレビューの表示とスクロールが従来どおりであること

### Phase 3 の着手点

- `y` の配線はビュー側が済んでいる。`TablePreviewView#copy_target` が生のセル値を返すので、
  `Clipboard.copy(view.copy_target)` を呼ぶだけでよい
- Files / Config モードの `y`（ファイルパスのコピー）は `KeybindHandler#dispatch` に `:copy_cell` を足す
- コピー結果の表示は 2 行目のステータス（`TablePreviewView#status_line`）に差し込む場所がある

## 18. Phase 3 実装記録

### 追加したファイル

| ファイル | 内容 |
|---|---|
| `lib/rufio/clipboard.rb` | OS コマンド（pbcopy / clip / wl-copy / xclip / xsel）→ OSC 52 の順で試すコピー。`available_method` / `available_command` はヘルスチェック用 |

変更: `preview_view.rb`（共通の `y` 処理と通知、`copy_target` の既定をファイルパスに）、
`table_preview_view.rb`（セル値のコピー、ステータス行への結果表示）、
`file_operation_controller.rb`（`copy_paths_to_clipboard`、選択パスの解決）、
`keybind_handler.rb`（`:copy_to_clipboard` の dispatch）、
`background_status.rb`（`notify` で即時操作の通知を出せるように）、
`config_loader.rb`（`copy_to_clipboard: 'y'`、`CLIPBOARD_COMMAND`）、
`health_checker.rb` と `config.rb`（クリップボードの検出とメッセージ）、`help_menu.rb`。

### 設計からの変更点

1. **アクション名を `copy_to_clipboard` にした**。設計では `copy_cell` だったが、表プレビュー以外では
   ファイルパスをコピーするため、名前と挙動が合わなくなる。`copy_selected`（ファイルのコピー）とも区別できる
2. **テキストプレビューの `y` もファイルパスのコピーにした**。Files モードと同じ意味にそろえた方が覚えやすく、
   「`y` はカーソルが指す一番細かいものをコピーする（表ならセル、それ以外はパス）」という一つの規則になる。
   ヒント行も `y: copy path  ESC: Back to files` に変えた
3. **コピー結果の通知を時間で消さず、次の操作まで出し続けるようにした**。設計では 1.5 秒表示としていたが、
   メインループは必要なときだけ再描画するため、時間で消す方式では消えるタイミングが再描画に依存してしまう。
   移動キーやホイールで通知を消す方式なら時計に依存せず、テストも書ける
4. **Files モードの通知は `BackgroundStatus#notify` に相乗りさせた**。ジョブ完了通知と同じ経路（最下行に 3 秒）で、
   新しい表示機構を増やさずに済む
5. **コマンドの存在確認は `which` を起動せず PATH を直接見る**ことにした（Windows では `PATHEXT` も見る）。
   既存の `HealthChecker` は `system("which ...")` を使っているが、これはキー入力ごとに走る処理であり、
   プロセス起動を避けたい。Windows に `which` がないという問題もない
6. **`Wayland` / `X11` のセッションがないときはコマンドを試さない**。SSH 越しの Linux では
   `DISPLAY` も `WAYLAND_DISPLAY` もないため、いきなり OSC 52 に進むのが正しい
7. **サイズ上限を 2 段にした**。全体で 100 KiB、OSC 52 では base64 後の長さで 74,994 バイト

### 動作確認

- 新規テスト `test_clipboard.rb` 18 ケース（プラットフォーム別の候補、設定コマンド、**シェルを経由しないこと**、
  OSC 52 の文字列と tmux / screen のラップ、サイズ上限、ヘルスチェック用の API）、
  `test_preview_view.rb` に 12 ケース、`test_table_preview.rb` に 1 ケース追加
- `rake test` 全体で新たな失敗はなし（既存の 13 件は変更前から発生している別件）
- tmux 上で `bin/rufio` を起動し、`CLIPBOARD_COMMAND` に標準入力をファイルへ書くスクリプトを設定して確認:
  CSV のセル（`R2C3` の `果物`）が余計な改行なしでそのままコマンドへ渡ること、
  テキストプレビューの `y` がファイルパスを渡すこと、
  Files モードで 2 件選択して `y` を押すと 2 行のパスが渡ること、
  ステータス行が `copied (configured)` になること、
  Files モードでは最下行に `data.tsv copied (configured)` が出て 3 秒後に消えること
- `rufio -c` にクリップボードの行が出ること（この環境ではコマンドがないため
  `OSC 52 (no clipboard command found)` と導入方法を表示）

### 残っている作業（Phase 4）

- `XlsxTableSource` / `SqliteTableSource`、シート切替（`[` / `]`）
- `Y`（行全体を CSV 1 行としてコピー）
- 検索画面のプレビューとの統合
