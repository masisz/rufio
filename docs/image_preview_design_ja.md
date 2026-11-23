# 画像プレビュー（Kitty グラフィックスプロトコル / Zig 版）設計メモ

## 1. 目的

プレビューペイン（分割・`P` のフルスクリーン）に画像を**そのまま表示**する。文字で近似する ASCII アート方式ではなく、端末のグラフィックス機能（Kitty graphics protocol）にピクセルを渡す。

- 対象形式: PNG / JPEG / GIF（1 枚目）/ BMP / TGA
- 対象端末: kitty、Ghostty、WezTerm、Konsole など Kitty プロトコルに応答する端末
- 使えない端末では**現状どおり**メタ情報のテキスト（形式・寸法・ファイルサイズ）を出すだけで、操作は一切止めない

### 非目標

| やらないこと | 理由 |
|---|---|
| Sixel / iTerm2 (OSC 1337) プロトコル | まず 1 つに絞る。プロトコル層を差し替え可能にしておき、後から足す（§12 Phase 5） |
| アニメーション GIF / APNG の再生 | 1 枚目だけ表示する。再生はメインループのフレーム設計に手が入る |
| SVG・PDF・RAW・HEIC | ベクタ／巨大デコーダが必要。SVG は従来どおりテキスト扱い |
| 画像の編集・回転・切り出し | ファイルマネージャの役目を越える（EXIF の回転だけは Phase 4 で検討） |

## 2. 現状

| いまの挙動 | 場所 |
|---|---|
| 拡張子で `type: 'image'` に分類されるが、中身は読まず「バイナリ」の文言を出す | `file_preview.rb:259`（`detect_file_type`）、`binary_response` |
| プレビューペインは 1 セル = 1 文字のバッファに描き、`Renderer` が**変更行だけ**を 1 回の `write` で出す | `screen.rb` / `renderer.rb:26` |
| プレビュー種別ごとの表示とキー操作は `PreviewView` の派生に閉じている（テキスト / 表） | `preview_view.rb`、`table_preview_view.rb` |
| 幅に依存する計算（折り返し・列幅・一致行）は `UIRenderer` が毎フレーム求め、ビューへ渡す | `ui_renderer.rb`、`apply_matches` / `visible_rows=` |
| ネイティブ処理は Zig の単一ライブラリに `core_*` の C ABI で生やし、Fiddle で引く。無い・古い・環境変数で無効なら Ruby にフォールバック | `lib_zig/rufio_native/src/main.zig`、`native_scanner_zig.rb`、`native_zip.rb` |

**画像は「セルに文字を書く」モデルから外れる**ので、既存の描画パイプラインに割り込み方を決めるのが設計の中心になる（§6）。

## 3. 責務の分割（なぜ Zig か）

CLAUDE.md の約束（安全性と方針は Ruby、計算はネイティブ）に合わせる。

| 層 | 担当 | 置き場所 |
|---|---|---|
| 端末能力の検出 | 問い合わせ・環境変数・tmux 判定・セルのピクセル寸法 | Ruby `terminal_graphics.rb` |
| プロトコル組み立て | APC シーケンス、Base64 の分割送信、配置・削除、tmux パススルー | Ruby `kitty_graphics.rb` |
| 配置の管理 | 画像 ID・矩形・再送条件・後片付け | Ruby `graphics_layer.rb` |
| 画像のデコード・縮小・符号化 | JPEG/GIF/BMP の展開、目標ピクセルへの縮小、PNG 再エンコード、Base64 化 | **Zig** `src/image.zig` |
| 方針・上限・フォールバック | 読み込み上限、ピクセル上限、形式判定、設定 | Ruby |

### Zig に置く理由

1. **Ruby に画像デコーダが無い**。`mini_magick` / `vips` を足すと外部コマンドや共有ライブラリへの依存が増え、「無くても動く」方針と合わない。Zig ライブラリは既に全 8 プラットフォーム分を gem に同梱している（`lib/rufio/native/<platform>/`）ので、置き場所が既にある。
2. **縮小が効く**。6000×4000 の JPEG をそのまま送ると Base64 で十数 MB になり、端末もデコードに時間を使う。ペインの実ピクセル（例 320×320）へ先に落とせば転送量は数十 KB になる。
3. **GVL の外で回せる**。既存の `AsyncScanner` / ZIP ジョブと同じく、自前スレッド＋ハンドルのポーリングで描画ループを止めない。

### Zig が無くても動く線

> Kitty プロトコルは **PNG を端末側でデコードできる**（`f=100`）。

したがって **PNG はファイルのバイト列をそのまま Base64 で送れば表示できる**。これを Zig 無しのフォールバック経路にする。

| 条件 | 挙動 |
|---|---|
| Kitty 対応 ＋ Zig あり | 全対象形式。ペインに合わせて縮小してから送る |
| Kitty 対応 ＋ Zig 無し（古いライブラリ・`RUFIO_NATIVE_IMAGE=0`） | PNG だけ直送（`max_bytes` 以下）。他形式はメタ情報テキスト |
| 非対応端末 / `IMAGE_PREVIEW.enabled = false` | メタ情報テキスト（従来どおり） |

「ネイティブ側だけに機能を実装しない」規約を満たすため、**Zig は速さと対応形式を増やすだけ**で、機能の有無を決めない。

## 4. 全体構成

```
┌─ 入力層 ────────────────────────────────────────────────┐
│ FilePreview          type: 'image' + メタ情報（形式・寸法・サイズ）│
│ ImageSource          シグネチャで形式を判定（拡張子は信用しない）   │
└──────────────────────────────────────────────────────────┘
          ↓ ImageDocument（パス・形式・元寸法・mtime）
┌─ 表示層 ────────────────────────────────────────────────┐
│ ImagePreviewView < PreviewView   ズーム・状態・ステータス行      │
│ UIRenderer                       セル矩形の確保とメタ情報の 1 行  │
└──────────────────────────────────────────────────────────┘
          ↓ 矩形（セル）＋ソース
┌─ 画像層 ────────────────────────────────────────────────┐
│ GraphicsLayer     どの画像をどこに置いたか／再送と削除の判断      │
│ KittyGraphics     APC シーケンスの組み立て（チャンク・tmux）      │
│ TerminalGraphics  対応判定・セルのピクセル寸法                  │
│ NativeImage       Zig 呼び出し（非同期）／PNG 直送のフォールバック │
└──────────────────────────────────────────────────────────┘
          ↓ 1 フレームの最後
   Renderer#render（セル差分）→ GraphicsLayer#flush（APC を後から書く）
```

**原則**: ターミナルへ直接 `print` しない規約は維持する。APC を書くのは `GraphicsLayer#flush` だけで、`Renderer` と同じ出力 IO を受け取り、**セル差分を書いた直後**に 1 回の `write` でまとめて出す。

## 5. Kitty プロトコルの使い方

### 5.1 送信

```
\e_G a=T, f=100, i=<id>, p=1, c=<cols>, r=<rows>, C=1, q=2, m=1 ; <base64 4096B> \e\\
\e_G m=1 ; <base64 4096B> \e\\
...
\e_G m=0 ; <base64 残り> \e\\
```

| キー | 値 | 意味 |
|---|---|---|
| `a=T` | — | 転送して即表示 |
| `f` | `100` / `24` / `32` | PNG / 生 RGB / 生 RGBA。生のときは `s=<px幅>,v=<px高さ>` も必須 |
| `t=d` | — | 直接転送（Base64）。既定 |
| `i` / `p` | 整数 | 画像 ID / 配置 ID。再送・削除の単位 |
| `c,r` | セル数 | 指定矩形に収める（アスペクト比は端末が保つ） |
| `C=1` | — | **カーソルを動かさない**（これが無いと行がずれて画面が崩れる） |
| `q=2` | — | 成功・失敗の応答を抑止（raw モードの入力ループに混ざらせない） |
| `m` | `1` / `0` | 分割送信の継続 / 最終チャンク。1 チャンクのペイロードは 4096 バイト以下 |

左上の位置は「送信時のカーソル位置」なので、`\e[<row>;<col>H` でペイン左上へ移動してから送り、`C=1` で動かさないまま終える。

### 5.2 削除・置き換え

| 操作 | シーケンス | いつ |
|---|---|---|
| 削除 | `\e_Ga=d,d=i,i=<id>,q=2\e\\` | 別のファイルを選んだ、プレビューを抜けた、矩形が変わった |
| 全削除 | `\e_Ga=d,d=A,q=2\e\\` | 終了処理（`cleanup_terminal`）、画面全体の再描画（`refresh_display`） |
| 再配置 | 同じ `i` で `a=p`（再送なし） | 画像は同じで矩形だけ動いた（ペイン幅の変更） |

**ID の決め方**: 他アプリと衝突させない。`i = 0x52000000 | ((pid & 0xffff) << 8) | slot`（slot は 0..3 の輪番）。`p` は矩形ごとに 1 ずつ増やす。

### 5.3 転送方式の選択

| 方式 | 使うとき | 注意 |
|---|---|---|
| `t=d`（直送） | 既定。SSH 越しでも動く | Base64 で 4/3 倍。縮小してから送るのが前提 |
| `t=t`（一時ファイル・読み込み後に端末が削除） | ローカルで 1 MB を超えるペイロード | 端末と同じホストでしか使えない。`/tmp` のパスを渡すので `RUFIO_IMAGE_TRANSFER=file` で明示的に有効化する扱い |
| `t=s`（共有メモリ） | 採らない | プラットフォーム差が大きく、得は小さい |

### 5.4 対応判定

1. `IMAGE_PREVIEW.enabled` が false なら即終了。
2. tmux / screen 内（`$TMUX` / `$STY`）は既定で無効。`tmux_passthrough: true` のときだけ `\ePtmux;` で `\e` を二重化して送る（tmux 3.3+ かつ `allow-passthrough on` が必要）。
3. 問い合わせ（起動直後、メインループに入る前に 1 回だけ）:
   ```
   送信: \e_Gi=31,s=1,v=1,a=q,t=d,f=24;AAAA\e\\  +  \e[c
   受信: \e_Gi=31;OK\e\\ を含めば対応。\e[?… だけ返って来たら非対応
   ```
   `\e[c`（Primary DA）を続けて送るのが要点で、**Kitty 非対応端末でも必ず何か返る**ため無応答で待たされない。読み取りは 200ms のタイムアウト付き、`raw` モードのまま `IO.select` で行い、取り切れなかったバイトは捨てる。
4. 環境変数（`TERM=xterm-kitty`、`KITTY_WINDOW_ID`、`TERM_PROGRAM=ghostty|WezTerm`）は**ヒントに留める**。判定は問い合わせ優先、問い合わせが失敗したときの保険に使う。
5. セルのピクセル寸法: `TIOCGWINSZ` の `ws_xpixel`/`ws_ypixel`（Zig の `core_image_cell_pixels`）。0 が返る端末では `CSI 16t` を試し、それも駄目なら 1 セル 8×16 と仮定する。

結果は `TerminalGraphics.capability`（`:kitty` / `:none`）としてプロセス内に 1 回だけ記憶し、`SIGWINCH` ではピクセル寸法だけ取り直す。

## 6. セル描画との整合（要点）

画像はセルバッファの外にあるので、**セル側が画像の上に書くと画像が壊れる**。次の 3 つで守る。

1. **矩形のセルを確保する**: `UIRenderer` は画像矩形を空白で埋め、`Screen#reserve(x, y, w, h)` で「画像占有」として記録する。確保セルは `put` / `put_string` を無視し（`Screen` 側で弾く）、通知やフッタが割り込んで画像を削るのを防ぐ。
2. **書き換えられたら再送する**: `Renderer#render` は書き換えた行番号の集合を返すようにする（現在は `true` / `false`）。`GraphicsLayer#flush(output, rewritten_rows:)` は、矩形と交差する行が書き換えられていたら**その画像だけ**再送する。
3. **変化が無ければ何も書かない**: 矩形・ソース（パス + mtime）・ズームが前フレームと同じで、交差する行も書き換わっていなければ APC を 1 バイトも出さない。これで静止時のコストが 0 になり、既存の「dirty 行だけ描く」方針と揃う。

### 再送・削除のきっかけ

| 変化 | 対応 |
|---|---|
| 選択ファイルが変わった | 旧画像を削除 → 新しい画像を 80ms のデバウンス後に送る（j/k の連打で MB 級の転送を繰り返さない） |
| プレビューを抜けた / モードが変わった / 検索画面を開いた | 削除のみ |
| ペイン幅・端末サイズが変わった | 矩形だけの変化なら `a=p` で再配置、ピクセル目標が大きく変わったら再デコード |
| ズーム（`+` / `-` / `0`） | 再デコードして再送 |
| 終了（`cleanup_terminal`） | `d=A` で全削除してから alternate screen を抜ける |

## 7. Zig 側の設計

### 7.1 C ABI（既存の `core_*` 命名・ハンドル方式に合わせる）

```c
const char* core_image_version(void);                       // API 世代（"1"）
int32_t core_image_cell_pixels(uint32_t* w, uint32_t* h);   // TIOCGWINSZ（失敗 -1）

// デコード＋縮小＋符号化を別スレッドで始める。戻り値はハンドル（0 は失敗）
uint64_t core_image_create(const char* path, size_t path_len,
                           uint32_t max_w, uint32_t max_h,
                           uint8_t format, uint32_t flags);
uint8_t  core_image_state(uint64_t handle);                 // 0=running 1=done 2=failed
int32_t  core_image_info(uint64_t handle, uint32_t* w, uint32_t* h,
                         uint32_t* src_w, uint32_t* src_h, uint8_t* kind);
const uint8_t* core_image_payload(uint64_t handle, size_t* len);  // Base64 済み
void     core_image_cancel(uint64_t handle);
void     core_image_destroy(uint64_t handle);
```

| 引数 | 意味 |
|---|---|
| `max_w` / `max_h` | 出力の上限ピクセル（ペインのセル数 × セルのピクセル）。超えるときだけ縮小し、拡大はしない |
| `format` | `0`=PNG 再エンコード（`f=100`）、`1`=RGB（`f=24`）、`2`=RGBA（`f=32`）、`3`=無変換の直送（PNG のみ） |
| `flags` | bit0: アルファを保つ、bit1: EXIF の回転を適用（Phase 4） |
| `kind` | 判定した形式（0=PNG 1=JPEG 2=GIF 3=BMP 4=TGA 255=非対応） |

- **戻りは Base64 済み**にする。数 MB の Base64 化を Ruby でやると GVL を握ったまま時間を使うため。4096 バイトごとの分割は Ruby 側で `byteslice` するだけにする。
- `format=1/2`（生ピクセル）は PNG 再エンコード（zlib 圧縮）を省けるので速い。ただし転送量は増える。**既定は `1`（RGB）**、アルファのある画像は `2`、`IMAGE_PREVIEW.transfer: 'png'` のときだけ `0`。
- エラーは state=failed と `kind=255` で表し、例外・ログは出さない（描画中に呼ばれるため）。

### 7.2 デコーダ

純 Zig の画像ライブラリ（`zigimg` 等）は依存追加と追従コストが大きいので、**`stb` 系の単一ヘッダを同梱して Zig で C としてコンパイルする**（`link_libc` は既に有効）。

| ファイル | 役割 | ライセンス |
|---|---|---|
| `src/vendor/stb_image.h` | PNG / JPEG / GIF / BMP / TGA のデコード | public domain (MIT 選択可) |
| `src/vendor/stb_image_resize2.h` | 縮小（既定は box、`quality: 'high'` で Mitchell） | 同上 |
| `src/vendor/stb_image_write.h` | PNG 再エンコード（`format=0` のときだけ） | 同上 |
| `src/vendor/stb.c` | 上記の実装を 1 回だけ展開する TU | — |

- `Makefile` / `build.zig` に `-I src/vendor src/vendor/stb.c` を足す。8 プラットフォームのクロスコンパイルは既存の `make dist` の仕組みに乗る（C を混ぜても Zig のクロスコンパイルで通る）。
- WebP / AVIF は stb が非対応。**拡張点**として `kind=255` を返すだけにし、将来 `libwebp` を同じやり方で足せる形にしておく。
- メモリは `std.c.malloc` / `free`（既存コードと同じ）。`STBI_MALLOC` などを差し替えて確保経路を 1 つにする。

### 7.3 安全性

| 危険 | 対策 |
|---|---|
| 細工した画像での巨大確保（decompression bomb） | デコード前に `stbi_info` で寸法を取り、`max_pixels`（既定 64M px = 8192×8192 相当）超は拒否。確保サイズは `w*h*4` を u64 で計算し桁溢れを検査 |
| 不正ファイルでのクラッシュ | stb は戻り値 NULL で失敗を返す設計。`kind=255` / failed に落とすだけで、プロセスは落とさない |
| 巨大ファイルの読み込み | `max_bytes`（既定 32 MiB）を超えるファイルは読まない（Ruby 側でも先に弾く） |
| パスの扱い | Ruby が渡す絶対パスのみ。Zig 側ではパスを組み立てない・書き込まない（読み取り専用で開く） |
| スレッド競合 | 既存 `AsyncScanner` と同じ mutex。`destroy` は実行中スレッドを join してから解放 |

## 8. Ruby 側の構成

| ファイル | 役割 |
|---|---|
| `lib/rufio/terminal_graphics.rb` | 対応判定（問い合わせ・環境変数・tmux）、セルのピクセル寸法、`supported?` / `cell_pixels` |
| `lib/rufio/kitty_graphics.rb` | `transmit(id:, payload:, format:, cols:, rows:, pixels:)` / `place` / `delete` / `delete_all` の**文字列組み立てだけ**（IO を持たない＝テストしやすい） |
| `lib/rufio/graphics_layer.rb` | 配置状態（id・矩形・ソース・ズーム）と `flush(output, rewritten_rows:)`、`clear_all` |
| `lib/rufio/native_image.rb` | Zig バインディング（`available?` / `decode_async` / ポーリング）と PNG 直送のフォールバック |
| `lib/rufio/image_source.rb` | シグネチャでの形式判定（PNG/JPEG/GIF/BMP）と寸法の読み取り（ヘッダだけ・Ruby で十分） |
| `lib/rufio/image_preview_view.rb` | `PreviewView` の種別。`image?`、ズーム、`y` でパスコピー、ステータス行 |
| 既存への追記 | `FilePreview`（`type: 'image'` にメタ情報）、`PreviewRegistry`（`image?`）、`PreviewView.build`、`UIRenderer`（矩形確保と登録）、`Screen#reserve`、`Renderer#render` の戻り値、`ConfigLoader.image_preview`、`HealthChecker`、`help_menu` と `info/` |

### 設定（`~/.config/rufio/config.rb`）

```ruby
IMAGE_PREVIEW = {
  enabled: true,            # false で完全に無効（従来のメタ情報表示）
  max_bytes: 32 * 1024 * 1024,
  max_pixels: 64_000_000,
  transfer: 'rgb',          # 'rgb' | 'rgba' | 'png'
  quality: 'fast',          # 'fast'（box）| 'high'（Mitchell）
  tmux_passthrough: false,
  debounce_ms: 80
}.freeze
```

`TABLE_PREVIEW` と同じく `DEFAULT_IMAGE_PREVIEW` / `MIN_` / `MAX_` で丸め、不正値は既定値のままにする。環境変数 `RUFIO_NATIVE_IMAGE=0` で Zig 経路だけを切る。

### キー操作（プレビューモード中）

| キー | 動作 |
|---|---|
| `+` / `-` | ズーム（等倍→ペイン収まりの倍率を 25% 刻み） |
| `0` | ペインに収める（既定） |
| `y` | ファイルパスをコピー（他のプレビューと同じ） |
| `ESC` | プレビューを抜ける（画像は削除） |
| `/` | 画像では検索しない（キーを食わずに `false` を返す） |

ステータス行（ファイル名の下）: `PNG 1920x1080  1.2 MB  →  640x360 (40x20 cells)  |  +/-: zoom  0: fit  ESC: back`

## 9. フォールバックの階段

```
IMAGE_PREVIEW.enabled?
  └─ no → メタ情報テキスト
TerminalGraphics.supported?            （問い合わせ → 環境変数 → tmux 判定）
  └─ no → メタ情報テキスト（「この端末は画像表示に対応していません」を 1 行）
NativeImage.available?                 （ライブラリ有無・API 世代・RUFIO_NATIVE_IMAGE）
  ├─ yes → 全形式・縮小あり
  └─ no  → PNG だけ直送（max_bytes 以下）／他形式はメタ情報テキスト
```

どの段でも**操作は止めない**。デコード中は「読み込み中」の 1 行を出し、完了したフレームで画像を出す。

## 10. 性能目標

| 項目 | 目標 |
|---|---|
| 2000×1500 JPEG → 320×320 px のデコード＋縮小 | 30 ms 以下（別スレッド。描画ループは止めない） |
| 転送量（上と同じ条件、`f=24`） | 400 KB 以下（Base64 込み）。PNG 再エンコードなら 60 KB 前後 |
| 静止時の 1 フレームあたり追加出力 | 0 バイト（変化が無ければ APC を出さない） |
| j/k で画像を連続で移動 | デバウンス 80 ms。移動中は削除のみ出し、止まってから 1 枚送る |
| キャッシュ | パス + mtime + 目標ピクセルで直近 4 枚、合計 8 MB まで（Base64 済みを保持） |

計測は `bench.sh` に倣って `lib_zig/rufio_native/bench_image.sh`（デコード＋縮小の単体）と、Ruby 側の「転送バイト数とフレーム数」を数えるベンチを置く。

## 11. テスト計画

| テスト | 内容 |
|---|---|
| `test/test_kitty_graphics.rb` | シーケンス組み立て: チャンク分割（4096 境界・最終チャンクの `m=0`）、`C=1`/`q=2` が必ず入る、削除、tmux パススルーの二重化 |
| `test/test_terminal_graphics.rb` | 擬似 IO に `\e_Gi=31;OK\e\\` を与えたら対応、`\e[?62;c` だけなら非対応、無応答はタイムアウトで非対応、`$TMUX` 時は既定で無効 |
| `test/test_graphics_layer.rb` | 変化が無ければ出力 0 バイト、矩形と交差する行が書き換えられたら再送、ファイル変更で削除＋再送、`clear_all` |
| `test/test_image_source.rb` | シグネチャでの形式判定（拡張子が嘘でも正しい）、ヘッダからの寸法読み取り、壊れたファイルは nil |
| `test/test_image_preview.rb` | `PreviewView.build` が画像で `ImagePreviewView` を返す、ズーム、`UIRenderer` が矩形を空白で確保しメタ情報を出す、非対応端末ではテキストに落ちる |
| Zig `src/image_test.zig` | PNG/JPEG の寸法、縮小のアスペクト比と上限、`max_pixels` 超の拒否、壊れた入力で failed、`destroy` 後にリークしない |
| パリティ | 同じ PNG を「直送」と「再エンコード」で送ったとき、`c,r` と見た目の寸法が一致する |
| CI | Windows・Linux の CI は端末が非対応なので、対応判定が false になり既存テストが落ちないことを確認（画像テストはスキップ扱い） |

## 12. 実装フェーズ

| Phase | 内容 | 目安 |
|---|---|---|
| 1 | **実装済み**: `TerminalGraphics`（検出）、`KittyGraphics`（組み立て）、`ImageSource`、`ImagePreviewView`、`GraphicsLayer`（最小）、`UIRenderer` の矩形確保、`Screen#reserve`、`Renderer#render` の戻り値、**PNG 直送だけ**で表示（Zig なしで動く）。直送の上限は 8 MiB（縮小が入る Phase 3 で広げる）。オーバーレイ（ヘルプ・検索画面・コマンドモード）中は画像を消す | 中 |
| 2 | **実装済み**: `GraphicsLayer` の再送（`Renderer#render` が返す行と矩形の交差）・削除・デバウンス（別ファイルへ移ったら先に消して 80ms 待つ）・Base64 キャッシュ（4 枚 / 8 MB、LRU）、終了処理と `refresh_display` の後片付け、ズーム（`+` / `-` / `0` と拡大中の `hjkl`。元画像の切り出し `x,y,w,h` を使うのでデコード不要）。矩形だけ変わったときの `a=p` 再配置は、部分実装の端末で表示が消える恐れがあるため採らず、キャッシュで転送を避ける方針にした | 中 |
| 3 | Zig `src/image.zig` ＋ stb 同梱、`core_image_*` API、`NativeImage`、JPEG/GIF/BMP 対応と縮小、8 プラットフォームのビルド更新 | 中〜大 |
| 4 | 設定（`IMAGE_PREVIEW`）、`HealthChecker` の端末グラフィックス検出、ヘルプ・`info/`・ガイド・README、EXIF 回転 | 小〜中 |
| 5 | （将来）Sixel / iTerm2 プロトコル、WebP、検索画面のプレビューへの展開 | 中 |

Phase 1 だけでも「PNG が端末で見える」価値が出る。Phase 3 を飛ばしても壊れないよう、Phase 1 の時点でフォールバックを先に作る。

## 13. 既知の制約

- **tmux / screen**: 既定で無効。`allow-passthrough on` の tmux 3.3+ でのみ設定で有効化でき、ペイン切り替え時に画像が残る端末がある
- **SSH 越し**: 直送のみ（`t=f` は使えない）。縮小前提で転送量を抑える
- **Windows**: Windows Terminal は Kitty プロトコル非対応。検出で無効になるだけ
- **アニメーション**: GIF は 1 枚目のみ
- **SVG / PDF / HEIC / RAW**: 非対応（SVG はテキスト扱いのまま）
- **半透明**: アルファは端末の背景と合成されるため、見た目は端末依存
- **フォントの行間**: セル寸法が取れない端末では 8×16 と仮定するため、アスペクト比がわずかにずれる

## 14. 参考

- Kitty graphics protocol: <https://sw.kovidgoyal.net/kitty/graphics-protocol/>
- Ghostty のグラフィックス対応: <https://ghostty.org/docs/vt/apc/kitty-graphics>
- `stb_image` / `stb_image_resize2` / `stb_image_write`: <https://github.com/nothings/stb>
- 既存の設計メモ: `docs/native_fuzzy_search_design_ja.md`（Zig と Ruby の分担・ベンチの作り方）、`docs/csv_cell_preview_design_ja.md`（`PreviewView` / `PreviewRegistry` の拡張点）
