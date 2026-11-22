# CSV セルプレビュー設計（行列表示 / hjkl セル移動 / y でクリップボードコピー）

対象バージョン: 1.7.0 想定（1.6.0 時点のコードを調査）
ステータス: 検討案（未実装）

## 1. 目的とスコープ

- `.csv` / `.tsv` をプレビューで**行列（グリッド）表示**する
- プレビューモード（`P`）で **`h` `j` `k` `l`** によりセルカーソルを移動する
- カーソル位置のセルを **`y`** でクリップボードへコピーする

スコープ外（将来候補として 13 章に記載）: セルの編集、ソート、表内検索、範囲選択、Excel (.xlsx) のグリッド表示。

## 2. 現状の調査結果（事実）

| 項目 | 現状 | 参照 |
|---|---|---|
| プレビュー生成 | `FilePreview#preview_file` が `{type:, lines:, ...}` を返す。`.csv` は `determine_file_type` の `else` に落ちて `type: "text"` 扱い | `lib/rufio/file_preview.rb:24`, `:135` |
| 読み込み上限 | 先頭 64 KiB（`MAX_PREVIEW_BYTES`）、既定 50 行（`DEFAULT_MAX_LINES`）、1 行 500 文字 | `lib/rufio/file_preview.rb:6-8`, `:108` |
| 文字コード | バイト読み → UTF-8 強制 → 不正バイトは `?` に置換 | `lib/rufio/file_preview.rb:111-116` |
| 行抽出 | `extract_preview_lines` は `'text' / 'code' / 'archive'` のみ `lines` を返し、**未知の type は「プレビュー不可」表示**になる | `lib/rufio/ui_renderer.rb:233-243` |
| 描画 | `draw_file_preview_to_buffer` が折り返し（`TextUtils.wrap_preview_lines`）＋ bat ハイライトを幅ごとにキャッシュして描画 | `lib/rufio/ui_renderer.rb:319-` |
| プレビューモード | `P`（`preview` アクション）でフルスクリーン。ヘッダ行に `[PREVIEW MODE]`、2 行目に `ESC: Back to files` | `lib/rufio/ui_renderer.rb:405-416` |
| プレビュー中のキー | `handle_preview_focus_key` が `j/k`（1 行）、`Ctrl+D/U`（20 行）、`ESC` のみ処理。**`h` / `l` / `y` / `0` / `$` は未使用** | `lib/rufio/navigation_controller.rb:222-237` |
| Files モードの `y` | `default_keybinds` に存在しない（未使用）。確認ダイアログの `y` は別入力ループ | `lib/rufio/config_loader.rb:47-89`, `lib/rufio/dialog_support.rb:26` |
| マウス | プレビュー中のホイールは `scroll_preview_up/down` を直接呼ぶ | `lib/rufio/terminal_ui.rb:698-703` |
| クリップボード | **実装が存在しない**（`pbcopy` / `xclip` / `wl-copy` / OSC 52 いずれの参照もなし） | `grep` 結果 0 件 |
| 依存 gem | `csv ~> 3.0` と `base64` は**すでに宣言済み**（`DocumentTextExtractor` が使用） | `rufio.gemspec`, `lib/rufio/document_text_extractor.rb:4-5` |
| 幅計算 | `TextUtils.char_width` / `display_width` / `truncate_to_width` / `pad_string_to_width` が全角対応済み | `lib/rufio/text_utils.rb:25,42,51,87` |
| 描画 API | `Screen#put_string(x, y, str, fg:, bg:)`、選択色は `ColorHelper.color_to_selected_ansi` | `lib/rufio/screen.rb:84`, `lib/rufio/ui_renderer.rb:306` |

重要な制約として、`NavigationController.new(listing, filter_manager)` の 2 引数呼び出しがテストから直接行われている（`test/test_navigation_mode_contracts.rb:31`）ため、引数追加はキーワード＋既定値にする必要がある。

## 3. 機能仕様

### 3.1 表示

分割ペイン・フルスクリーンの両方でグリッド表示する（カーソルはプレビューモード中のみ描画）。

```
 sales.csv [PREVIEW MODE]
 R3C2 price | hjkl: move  y: copy  ESC: back            copied (pbcopy)
     | A name       | B price | C stock |
   1 | apple        |     120 |      30 |
   2 | banana       |      80 |      12 |
   3 | みかん       |     150 |       8 |      <- C2 セルを反転表示
   4 | ...
     +-- 3 cols hidden (l to scroll) --  1000/4821 rows (truncated)
```

- 1 行目: 既存のファイル名ヘッダ（変更なし）
- 2 行目: 既存のヒント行を拡張し、セル番地・列名・操作ヒント・コピー結果を表示
- 左に行番号ガター、ヘッダ行（既定で 1 行目）は縦スクロール中も固定表示
- カーソルセルは反転（`ColorHelper.color_to_selected_ansi`）
- 列幅に収まらないセルは `truncate_to_width` で切り詰め（末尾 `…`）
- 切り詰め（行数・列数・バイト数）が発生した場合は最下行に明示

### 3.2 キー（プレビューモード中かつ表プレビューのとき）

| キー | 動作 |
|---|---|
| `h` / `l` | 左 / 右のセルへ（`ConfigLoader.keybinds[:navigate_parent]` / `[:navigate_enter]` を参照） |
| `j` / `k` | 下 / 上のセルへ（`[:move_down]` / `[:move_up]` を参照） |
| 矢印キー | 同上 |
| `Ctrl+D` / `Ctrl+U` | 1 画面分の行移動（既存の 20 行を踏襲） |
| `g` / `}` | 先頭行 / 最終行（Files モードの `top` / `bottom` に合わせる） |
| `0` / `$` | 行の先頭列 / 末尾列 |
| `y` | カーソルセルの**生の値**をクリップボードへ |
| `ESC` | ファイル一覧へ戻る |

表以外のファイルでは従来どおり（`j/k` スクロール、`h/l/y` は無反応）。マウスホイールは行スクロールに割り当てる。

## 4. アーキテクチャ

### 4.1 新規ファイル

| ファイル | 責務 |
|---|---|
| `lib/rufio/table_data.rb` | パース結果の値オブジェクト（セル配列・区切り・文字コード・切り詰めフラグ） |
| `lib/rufio/table_preview.rb` | CSV/TSV のパース、文字コード判定、上限適用、パス+mtime+size キャッシュ |
| `lib/rufio/table_layout.rb` | 幅依存のレイアウト計算（列幅・ガター幅・可視列）と 1 行分の文字列生成 |
| `lib/rufio/table_cursor.rb` | セルカーソル（row/col）と行・列スクロール、クランプ |
| `lib/rufio/clipboard.rb` | クリップボードへのコピー（OS コマンド → OSC 52 フォールバック） |

### 4.2 既存ファイルの変更

| ファイル | 変更 |
|---|---|
| `file_preview.rb` | `table_file?` 判定を追加し、`type: 'table'`・`table:`（`TableData`）・`lines:`（整形済みグリッド文字列、互換フォールバック）を返す |
| `ui_renderer.rb` | `extract_preview_lines` に `'table'` を追加（**必須**。無いと分割ペインが「プレビュー不可」になる）／`draw_table_preview_to_buffer` を追加／`@preview_cache[path][:table_layout][safe_width]` にレイアウトをキャッシュ |
| `navigation_controller.rb` | `focus_preview_pane` で表ファイルなら `TableCursor` を生成、`unfocus_preview_pane` で破棄、`handle_preview_focus_key` を表モードと従来モードに分岐。コンストラクタは `table_loader: TablePreview` のキーワード追加（既定値ありで後方互換） |
| `keybind_handler.rb` | `dispatch` に `:copy_cell` を追加（Files モードでの扱いは 12 章の未決事項） |
| `config_loader.rb` | `default_keybinds` に `copy_cell: 'y'`、`CSV_PREVIEW` / `CLIPBOARD_COMMAND` 設定を追加 |
| `health_checker.rb` | クリップボード手段の検出（`rufio -c` に表示） |
| `help_menu.rb`, `info/help.md`, `info/keybindings.md`, `README*.md`, `docs/guide*.md`, `CHANGELOG.md` | ドキュメント追記 |

### 4.3 データフロー

```
FilePreview#preview_file(path)
  └─ table_file?(path) → TablePreview.load(path) → TableData
       └─ {type:'table', table: TableData, lines: [整形済み行], ...}
            ├─ UIRenderer（分割/フルスクリーン）: TableLayout.build(table, safe_width) → グリッド描画
            └─ NavigationController: focus 時に TableCursor.new(table) を保持 → キー処理 → y で Clipboard.copy
```

パースは `TablePreview` 内のキャッシュ（キー: パス+mtime+size、容量 4 件程度）で 1 回に抑え、分割ペイン描画とプレビューモードで共有する。`UIRenderer` の既存プレビューキャッシュとは役割を分け、レイアウト（幅依存）だけを `@preview_cache` 側に置く。

### 4.4 データ構造（案）

```ruby
TableData = Struct.new(
  :rows,            # Array<Array<String>> 生のセル値（セル内改行を保持）
  :header,          # Array<String> | nil（1行目をヘッダ扱いする場合）
  :delimiter,       # "," | "\t" | ";"
  :encoding,        # "UTF-8" | "CP932" | ...
  :row_truncated,   # 行数上限に到達
  :col_truncated,   # 列数上限に到達
  :byte_truncated,  # バイト上限で切った
  :total_rows_hint, # 推定総行数（切り詰め表示用、不明なら nil）
  keyword_init: true
)
```

`TableLayout` は `col_widths`、`gutter_width`、`visible_columns(col_offset, width)`、`render_row(row_index, cursor_col)` を提供し、幅が変わったときだけ再計算する。

## 5. パースの詳細

### 5.1 区切り文字

- `.csv` → `,` / `.tsv` `.tab` → `\t`
- `.csv` で 1 行目に `;` が `,` より明らかに多い場合は `;` と推定（欧州式 CSV）。設定 `delimiter:` で固定可能
- 推定は 1 行目だけに限定し、外れたときは設定で直せることをドキュメントに明記

### 5.2 文字コード（日本語 CSV で最重要）

現状は UTF-8 強制＋不正バイトを `?` に置換するため、CP932（Shift_JIS）の CSV は全面的に化ける（`file_preview.rb:111-116`）。

- 最小案: UTF-8 BOM を除去するのみ（CP932 は化けたまま）
- **推奨案**: BOM 判定 → UTF-8 として `valid_encoding?` なら UTF-8 → そうでなければ CP932 として `encode('UTF-8')` を試行 → それも失敗したら従来の置換付き UTF-8
- クリップボードへは常に UTF-8 に正規化した値を渡す
- 設定 `encoding:` で明示指定（`'auto'` 既定）

### 5.3 上限

| 項目 | 既定 | 理由 |
|---|---|---|
| バイト | 64 KiB（既存 `MAX_PREVIEW_BYTES` を流用、設定で 1 MiB まで引き上げ可） | 既存のプレビュー応答性方針に合わせる |
| 行 | 1,000 | 60 fps のループを阻害しない範囲 |
| 列 | 256 | 横スクロールが現実的な範囲 |
| 列幅 | 最小 3、最大 32 文字 | 極端なセルで表が崩れないように |

切り詰めた行・列へはカーソルを移動できない（＝`y` でコピーできる範囲と表示範囲が一致し、誤解を生まない）。切り詰めの事実は最下行に表示する。

### 5.4 壊れた CSV / 特殊なセル

- `CSV::MalformedCSVError`（引用符の不整合など）→ `liberal_parsing: true` で再試行 → それでも失敗なら**従来のテキストプレビューにフォールバック**し、ヘッダに `(not parsed as table)` を付す
- セル内の改行・タブは表示時に半角スペース 1 個へ畳む（記号に置換すると等幅が崩れる端末がある）。`y` は生の値（改行込み）をコピー
- 空行は空セル 1 つの行として表示（行番号を飛ばさない）
- ヘッダ行の有無は設定（既定 `header: true`）。自動推定は誤判定時の混乱が大きいため採用しない

## 6. 描画の詳細

- 列幅は読み込んだ全行（最大 1,000 行）を `TextUtils.display_width` で走査して算出。コストが問題になる場合は先頭 200 行に限定
- パディングは `TextUtils.pad_string_to_width`、切り詰めは `truncate_to_width`。`wrap_preview_lines`（折り返し）は使わない
- 横スクロール: `col_offset` から可視幅に入る列を詰める。カーソルが可視範囲外になったら最小移動で `col_offset` を調整
- 縦スクロール: 既存の `preview_scroll_offset` と同じ考え方で、ヘッダ行は常に先頭に固定
- 狭い分割ペイン: 可視列が 0 になる場合はまず行番号ガターを省略、それでも入らなければ 1 列だけ表示、幅 20 桁未満なら従来のテキスト表示へフォールバック
- 非フォーカス（分割ペイン）時はカーソルを描画しない
- bat ハイライトは `type == 'code'` のみが対象（`ui_renderer.rb:353`）なので表プレビューには影響しない

## 7. クリップボード設計

```ruby
Rufio::Clipboard.copy(text) # => :pbcopy | :clip | :wl_copy | :xclip | :xsel | :osc52 | false
```

優先順:

1. 設定 `CLIPBOARD_COMMAND`（argv 配列で指定）
2. OS 既定
   - macOS: `pbcopy`
   - Windows: `clip`（PowerShell の `Set-Clipboard` は起動が重いので第 2 候補）
   - Linux / BSD: `WAYLAND_DISPLAY` があれば `wl-copy`、`DISPLAY` があれば `xclip -selection clipboard` → `xsel --clipboard --input`
3. OSC 52 フォールバック（SSH 越しでも効く。端末側の対応に依存）

実装方針:

- 実行は `IO.popen(argv, 'w')` の **argv 配列**で行い、シェルを経由しない（`file_opener.rb:123` と同じ方針、`SECURITY.md` の方針に沿う）
- コマンドの存在確認は 1 回だけ行って結果をメモ化（毎回 `which` を起動しない）
- OSC 52: `"\e]52;c;#{Base64.strict_encode64(text)}\a"` を STDOUT へ書いて `flush`。既存コードも `print` で制御シーケンスを直接出しており（`terminal_ui.rb:142-183`）、方式として矛盾しない
  - `TMUX` 環境では DCS パススルー（`\ePtmux;` ＋ ESC を `\e\e` にエスケープ ＋ `\e\\`）が必要で、tmux 側の `set -g set-clipboard on` も必要
  - `TERM` が `screen*` の場合は DCS チャンク分割が必要
  - OSC 52 は**成否が取得できない**ため、未対応端末では無言で失敗する
- そのため「どの手段でコピーしたか」を 2 行目に短時間（約 1.5 秒）表示する（`copied (pbcopy)` / `copied (OSC52)`）。失敗時は `clipboard unavailable`
- サイズガード: セル単体なら問題ないが、将来の行コピー・範囲コピー向けに 100 KiB で打ち切る
- `base64` は既に依存にあるため新規依存は不要
- `rufio -c`（`HealthChecker`）に検出結果を追加し、どの手段が使えるかを事前に確認できるようにする

## 8. キーバインドの競合

- プレビューモード中の `h` / `l` / `y` / `0` / `$` は現在未使用（`navigation_controller.rb:222` の `case` に無い）→ **競合なし**
- Files モードの `y` も `default_keybinds` に無く未使用。確認ダイアログの `y` は別の入力ループなので影響なし
- セル移動は `ConfigLoader.keybinds` の `move_up` / `move_down` / `navigate_parent` / `navigate_enter` を参照し、ユーザーの hjkl 変更に追従させる（現状 `handle_preview_focus_key` は `'j'` / `'k'` のハードコード。既定値では挙動は変わらない）
- `default_keybinds` に `copy_cell: 'y'` を追加すると `build_key_map`（`keybind_handler.rb:461`）経由で **Files モードでも `y` が dispatch される**。`dispatch` に `:copy_cell` を追加し、表プレビュー外での動作を決める必要がある（12 章）

## 9. 既存機能への影響と互換性

| 影響 | 対応 |
|---|---|
| `extract_preview_lines` が未知 type を「プレビュー不可」にする | `'table'` を分岐に追加（必須） |
| 検索画面のプレビュー（`FuzzyPreviewLoader`）は別経路 | `lines:` フォールバックにより整形済みグリッド文字列がそのまま表示される（カーソル操作なし）。Phase 4 で統合を検討 |
| `NavigationController.new` の 2 引数呼び出し（テスト） | 追加引数はキーワード＋既定値 |
| `global_search` の CSV 読み取り | `DocumentTextExtractor` の別経路で無関係 |
| `type` 変更による既存テスト | `test_file_preview.rb` 等で `.csv` を `text` と見なす箇所があれば更新 |

## 10. テスト計画

新規:

- `test/test_table_preview.rb`: 区切り推定、BOM、CP932、行/列/バイト上限、`MalformedCSVError` → `liberal_parsing` → テキストフォールバック、セル内改行の保持
- `test/test_table_layout.rb`: 列幅算出（全角混在）、横スクロール時の可視列、狭幅フォールバック
- `test/test_table_cursor.rb`: hjkl のクランプ、ページ移動、カーソル追従スクロール
- `test/test_clipboard.rb`: `RbConfig` / `ENV` をスタブした手段選択、OSC 52 文字列（tmux ラップ含む）、コマンド不在時のフォールバック、**シェルを経由しないこと**
- `test/test_csv_cell_preview_integration.rb`: fixture CSV で `P` → `hjkl` → `y`（`Clipboard` をスタブ）して期待セルが渡ることを確認

更新: `test_file_preview.rb` / `test_ui_renderer.rb`（`ui_test_harness.rb` でグリッド行を検証）/ `test_keybind_config.rb`（`copy_cell`）/ `test_preview_scroll.rb`（非表ファイルの挙動不変）/ `test_info_docs.rb`（`info/*.md` の整合チェックに行を追加）

fixture（`test/fixtures/`）: 全角混在、引用符、セル内改行、CP932、引用符が壊れた CSV、TSV の各小ファイル。

## 11. 実装フェーズ

| Phase | 内容 | 目安 |
|---|---|---|
| 1 | `TableData` / `TablePreview` / `TableLayout`、`FilePreview` の type 追加、分割＋フルスクリーンのグリッド表示（カーソルなし） | 中 |
| 2 | `TableCursor`、`handle_preview_focus_key` の分岐、hjkl・ページ・`0`/`$`・`g`/`}`、2 行目のステータス表示、マウスホイール | 中 |
| 3 | `Clipboard`、`y`（`copy_cell`）、コピー結果表示、`HealthChecker` 追加、設定項目、ドキュメント | 小〜中 |
| 4 | 文字コード自動判定の強化、`Y`（行コピー）、検索画面プレビューとの統合、`.xlsx` の表表示（`roo` は依存済み） | 任意 |

Phase 1 単体でも「CSV が表で読める」価値があり、Phase 2・3 を分けて入れられる。

## 12. 未決事項（判断が必要）

1. **Files モードでの `y`**: 表プレビュー外で押されたときに (a) 何もしない、(b) カーソル中のファイルの絶対パスをクリップボードへコピーする。(b) は有用だが「`y` の意味」が 2 つになる
2. **文字コード**: CP932 自動判定を Phase 1 に含めるか（日本語 CSV では実用上ほぼ必須と思われる）、Phase 4 に回すか
3. **ヘッダ行**: 既定で 1 行目をヘッダ扱いしてよいか（`header: false` の設定を用意する前提）
4. **バイト上限**: CSV だけ 64 KiB より大きくするか（例: 256 KiB）。大きくすると表示できる行が増える一方、パース時間が伸びる
5. **OSC 52 の扱い**: 未対応端末で無言失敗するため、フォールバックとして常に有効にするか、設定で明示的に有効化させるか
6. **コピー対象**: `y` は生の値のみか、`Y` で行全体（CSV 1 行）も入れるか

## 13. 将来の拡張候補

セル範囲選択（`v` + hjkl）、列ソート、表内検索（`/` で絞り込み）、列の固定（先頭列ピン留め）、`.xlsx` / `.ods` のシート表示（`roo` 依存済み）、数値列の右寄せ・桁区切り表示、セル値の型推定による色分け。
