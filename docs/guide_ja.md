# rufio 操作ガイド

**日本語** | [English](./guide.md)

rufio 1.3 以降の操作をまとめたガイドです。インストールと概要は [README](../README_ja.md) を参照してください。
rufio の中ではいつでも `?` でヘルプメニューを開けます。

## 目次

- [画面とモード](#画面とモード)
- [移動](#移動)
- [プレビュー](#プレビュー)
- [ファイル操作](#ファイル操作)
- [ZIP の展開・圧縮](#zip-の展開圧縮)
- [フィルターと検索](#フィルターと検索)
- [横断検索（G モード）](#横断検索g-モード)
- [ブックマークと履歴](#ブックマークと履歴)
- [コマンドモード](#コマンドモード)
- [スクリプト](#スクリプト)
- [DSL コマンド](#dsl-コマンド)
- [ジョブとログ](#ジョブとログ)
- [Config モード](#config-モード)
- [シェル連携](#シェル連携)
- [設定](#設定)
- [外部ツール](#外部ツール)
- [コマンドラインオプション](#コマンドラインオプション)
- [ネイティブエンジン](#ネイティブエンジン)

## 画面とモード

Files モードでは、最上段に現在のパス、その下にブックマーク一覧、左にファイル一覧、右にプレビューを表示します。最下段はモードのタブです。

| キー | モード |
|------|--------|
| （起動時） | **Files** – ファイルの閲覧と操作 |
| `C` | **Config** – `~/.config/rufio/` を Files と同じ操作で閲覧 |
| `G` | **Search** – 全ブックマーク配下のファイル名・内容を横断検索 |
| `L` | **Logs** – コマンド実行ログの閲覧 |
| `J` | **Jobs** – バックグラウンドのコマンド・スクリプト・ZIP 処理 |
| `?` | **Help** – 現在の画面の上に開くヘルプメニュー |

`ESC` で現在のモードを抜けます。Files・Config 以外のモードでは、`Shift+Tab` で前のモードに切り替わります。

## 移動

| キー | 操作 |
|------|------|
| `j` / `↓` | 下へ |
| `k` / `↑` | 上へ |
| `h` / `←` | 親ディレクトリへ |
| `l` / `→` / `Enter` | ディレクトリに入る |
| `g` | 先頭へ |
| `}` | 末尾へ |
| `R` | 再読み込み |
| `0` | 起動したディレクトリへ戻る |
| `q` | 終了（確認あり） |
| `T` | 終了して、シェルを現在のディレクトリへ移動（[シェル連携](#シェル連携)） |

マウスでも、クリックで選択、ホイールで一覧やプレビューをスクロールできます。

## プレビュー

右側のペインに選択中のファイルを表示します。`bat` があればコードをハイライトします。`.zip` は展開せずにエントリ一覧（サイズ・圧縮方式・更新日時・名前）を表示します。

| キー | 操作 |
|------|------|
| `P` | 全画面プレビュー（ファイル一覧を隠す） |
| `j` / `k` | スクロール |
| `Ctrl+D` / `Ctrl+U` | 1 ページ下 / 上 |
| `ESC` | ファイル一覧に戻る |

## ファイル操作

| キー | 操作 |
|------|------|
| `o` | ファイルを対応するアプリで開く（[設定](#設定) の `APPLICATIONS`） |
| `e` | 現在のディレクトリを OS のファイルエクスプローラーで開く |
| `a` | ファイル作成 |
| `A` | ディレクトリ作成 |
| `r` | リネーム |
| `d` | 削除（確認あり） |
| `Space` | 選択 / 選択解除 |
| `m` | 選択したアイテムを現在のディレクトリへ移動 |
| `c` | 選択したアイテムを現在のディレクトリへコピー |
| `x` | 選択したアイテムを削除（確認あり） |

移動・コピーは、`Space` で選択してから移動先のディレクトリへ行き、`m` または `c` を押します。
コピー先に同じ名前がある場合は連番を付けてコピーします（`name_1.txt`、`dir_1`）。移動先に同じ名前がある場合はエラーになります。

## ZIP の展開・圧縮

`Space` でアイテムを選択して `z` を押します。

- **選択がすべて `.zip` の場合**: それぞれを現在のディレクトリの `<名前>/` に展開します（同名があれば `<名前> 2/`、`<名前> 3/` …）
- **それ以外の場合**: アーカイブ名を尋ねたうえで、選択したアイテムを現在のディレクトリに 1 つの `.zip` として圧縮します。`Enter` で提案された名前（1 件なら `<アイテム名>.zip`、複数なら `Archive.zip`）を使います

処理はジョブとして実行されます。進捗の確認とキャンセルは Jobs モードで行います（`J` → `x`）。展開に失敗・キャンセルした場合は途中まで展開したフォルダを削除し、完了するとファイル一覧を更新します。

展開時は書き込み前にアーカイブ全体を検証します。パストラバーサル・絶対パス・データ範囲が重なるエントリ、合計 16 GiB・10 万エントリ・圧縮率 1000:1（1 MiB 超のエントリ）を超えるアーカイブを拒否します。シンボリックリンクと暗号化エントリはスキップし、CRC-32 を検証し、既存ファイルは上書きしません。対応する圧縮方式は Stored と Deflate です。

何も選択していないときの `z` は zoxide 履歴を開きます。

## フィルターと検索

| キー | 操作 |
|------|------|
| `f` | 入力に合わせて一覧を絞り込む（`Enter` で確定、`ESC` で解除） |
| `s` または `/` | fzf でファイル名検索 |
| `F` | rga でファイル内容検索 |
| `G` | 全ブックマークを横断検索（外部ツール不要） |

## 横断検索（G モード）

`G` で、ブックマークした全ディレクトリの配下を再帰的に検索します。先に `b` でブックマークを登録してください。

| キー | 操作 |
|------|------|
| 文字入力 | 大文字・小文字を区別しない部分一致検索 |
| `Tab` | **File names（ファイル名）** と **Content（内容）** を切り替え |
| `↑` / `↓`、`Ctrl+N` / `Ctrl+P` | 結果を選択 |
| `Enter` | Files モードでそのファイルの場所へ移動 |
| `Ctrl+U` | 検索語をクリア |
| `ESC` | 元のモードに戻る |

- 一致箇所はハイライトされます。内容検索ではファイル・行番号・一致した行を表示します。
- 検索中は黄色の `Searching...` が動き、完了すると緑の `Search complete` に変わります。
- アクセスできないディレクトリとディレクトリのシンボリックリンクはスキップします。通常のテキストは UTF-8 として読み、先頭 8 KB に NUL バイトがあるファイルはバイナリとして扱います。

### 文書の内容検索

Python・Microsoft Office・変換ツールなしで文書の中も検索できます。

| ファイル | 検索する内容 | 結果の位置 |
|----------|--------------|------------|
| `.pdf` | 抽出できる文字列 | ページ |
| `.xlsx` | セルの文字列と保存済みの値 | シートとセル |
| `.pptx` | スライドの図形・表内の文字列 | スライド |

抽出した文字列はメモリにキャッシュし（最大 64 文書・約 16 MiB）、ファイルが変わると再抽出します。画像だけの PDF には OCR が必要で、これは含みません。旧形式の `.xls` / `.ppt` とスライドノートは対象外です。

### 拡張子の除外

`~/.config/rufio/config.rb` に次を追加して rufio を再起動します。ファイル名・内容の両方に適用されます。

```ruby
GLOBAL_SEARCH_EXCLUDED_EXTENSIONS = %w[.png .jpg .zip .tar.gz .log].freeze
```

大文字・小文字は区別せず、先頭のドットは省略できます。デフォルトの `[]` は何も除外しません。

## ブックマークと履歴

| キー | 操作 |
|------|------|
| `b` | 現在のディレクトリをブックマーク |
| `B` | ブックマークメニュー |
| `1`〜`9` | ブックマーク 1〜9 へ移動 |
| `Tab` / `Shift+Tab` | 次 / 前のブックマークへ（Files・Config モード） |
| `z` | zoxide 履歴（何も選択していないとき） |

`B` のメニュー:

1. 現在のディレクトリをブックマークに追加
2. 現在のディレクトリをスクリプトパスに追加
3. スクリプトパスの管理（`d` で削除、`Enter` で移動、`ESC` で閉じる）
4. ブックマーク一覧

## コマンドモード

`:` でコマンドモードを開きます。`Tab` で補完、`↑` / `↓` で履歴、`Enter` で実行、`ESC` でキャンセルです。

| 入力 | 動作 |
|------|------|
| `@名前` | スクリプトパスまたは現在のディレクトリのスクリプトを実行 |
| `rake:タスク` | 現在のディレクトリの `Rakefile` のタスクを実行 |
| `!コマンド` | シェルコマンドをバックグラウンドで実行 |
| `cd <パス>` | ディレクトリへ移動 |
| `名前` | 組み込みコマンド・DSL コマンドを実行 |

```
:@build              # スクリプト（Tab で名前を補完）
:rake:test           # Rake タスク（Rakefile・rakefile・Rakefile.rb に対応）
:!git status         # シェルコマンド
:hello               # 組み込みのサンプルコマンド
```

### パスへ移動

`:cd` の後ろにパスを貼り付けると、その場所へ移動します。

```
:cd ~/projects/app             # ディレクトリ
:cd '/path/with space/a.txt'   # ファイル: フォルダへ移動してそのファイルを選択
:cd sub                        # 現在のディレクトリからの相対パス
:cd -                          # 直前のディレクトリへ戻る
:cd                            # ホームディレクトリ
```

コピー時に付く両端の引用符・末尾の改行・`\ ` エスケープ・`file://` URL はそのまま受け付けます。`Tab` でディレクトリ名を補完できます。パスが存在しない場合は移動せずにエラーを表示します。

## スクリプト

登録したスクリプトパスと、いま開いているディレクトリにあるスクリプトを `:@名前` で実行できます。実行時の作業ディレクトリは、いま開いているディレクトリです。

| 拡張子 | 実行に使うもの |
|--------|----------------|
| `.rb` | Ruby |
| `.py` | Python 3 |
| `.sh` | シェル |
| `.js` | Node.js |
| `.ts` | ts-node |
| `.pl` | Perl |
| `.ps1` | PowerShell |

スクリプトパスは次の順に探し、最初に名前が一致したものを使います。

1. プロジェクトの `./rufio.yml`
2. `~/.config/rufio/script_paths.yml`
3. `/etc/rufio/script_paths.yml`

ディレクトリを登録するには、rufio でそのディレクトリを開いて `B` → `2` を押します。

## DSL コマンド

`~/.config/rufio/commands.rb`（`~/.rufio/commands.rb` も可）に独自コマンドを定義し、`:名前` で実行します。

```ruby
command "hello" do
  ruby { "Hello from rufio!" }
  description "挨拶コマンド"
end

command "status" do
  shell "git status"
  description "Gitステータス"
end

command "build" do
  script "~/.config/rufio/scripts/build.rb"
  description "ビルド実行"
end
```

## ジョブとログ

シェルコマンド・スクリプト・ZIP 処理はバックグラウンドで実行され、その間もファイル操作を続けられます。ジョブが終わると通知が出ます。

**Jobs モード（`J`）**

| キー | 操作 |
|------|------|
| `j` / `k` | ジョブを選択 |
| `g` / `G` | 先頭 / 末尾のジョブ |
| `Space` | ジョブのログを表示 |
| `x` | 選択したジョブをキャンセル |
| `ESC` | 戻る |

**Logs モード（`L`）** は `~/.config/rufio/logs/` の実行ログを一覧表示します。`P` でログをプレビューし、`ESC` でプレビューを閉じ、もう一度 `ESC` で Files に戻ります。

## Config モード

`C` で `~/.config/rufio/` を開きます（なければ作成します）。移動・プレビュー・ファイル操作は Files モードと同じなので、設定やスクリプトを直接編集できます。設定ディレクトリの外へ移動すると Files モードに戻ります。

## シェル連携

`rufio --shell-init` は `rf` というシェル関数を出力します。`rf` で rufio を起動して `T` を押すと、終了してシェルが表示中のディレクトリへ移動します。`q` で終了した場合は移動しません。

```bash
# bash / zsh（~/.bashrc または ~/.zshrc）
eval "$(rufio --shell-init)"

# fish（~/.config/fish/config.fish）
rufio --shell-init fish | source
```

```powershell
# PowerShell（$PROFILE）
Invoke-Expression (& rufio --shell-init powershell | Out-String)
```

引数を省略すると、Windows では PowerShell 用、それ以外ではログインシェル（`bash`・`zsh`・`fish`）用を出力します。シェル起動のたびに Ruby を起動したくない場合は、`rufio --shell-init >> ~/.bashrc` のように一度だけ出力を追記してください。

## 設定

```
~/.config/rufio/
├── config.rb          # メイン設定（Ruby の定数）
├── script_paths.yml   # スクリプトパス
├── bookmarks.yml      # ブックマーク
├── commands.rb        # DSL コマンド
├── scripts/           # 個人スクリプト
└── logs/              # 実行ログ
```

### config.rb

```ruby
# ~/.config/rufio/config.rb

# 'en' または 'ja'（環境変数 RUFIO_LANG でも指定可）
LANGUAGE = 'ja'

# 色（HSL）
COLORS = {
  directory: { hsl: [220, 80, 60] },
  file: { hsl: [0, 0, 90] },
  executable: { hsl: [120, 70, 50] },
  selected: { hsl: [50, 90, 70] },
  preview: { hsl: [180, 60, 65] }
}.freeze

# キーの変更はアクション名で指定する。値は 1 キーの文字列
KEYBINDS = {
  bottom: 'G',
  global_search: 'S'
}.freeze

# `o` で使うアプリ（拡張子ごと）
APPLICATIONS = {
  %w[txt md rb py js json yml] => 'code',
  :default => 'open'
}.freeze

# G モードの検索から除外する拡張子
GLOBAL_SEARCH_EXCLUDED_EXTENSIONS = %w[.log].freeze
```

`KEYBINDS` で使えるアクション名:

| 分類 | アクション（デフォルトキー） |
|------|------------------------------|
| 移動 | `move_up` (k), `move_down` (j), `navigate_parent` (h), `navigate_enter` (l), `top` (g), `bottom` (}), `refresh` (R) |
| ファイル | `open_file` (o), `preview` (P), `rename` (r), `delete` (d), `create_file` (a), `create_dir` (A), `move_selected` (m), `copy_selected` (c), `delete_selected` (x), `open_explorer` (e) |
| 選択・検索 | `select` (Space), `filter` (f), `fzf_search` (s), `fzf_search_alt` (/), `rga_search` (F) |
| ブックマーク | `add_bookmark` (b), `bookmark_menu` (B), `zoxide` (z), `start_dir` (0) |
| モード | `job_mode` (J), `global_search` (G), `config_mode` (C), `help` (?), `log_viewer` (L), `command_mode` (:), `quit` (q), `quit_cd` (T) |

### script_paths.yml と bookmarks.yml

```yaml
# ~/.config/rufio/script_paths.yml
- ~/.config/rufio/scripts
- ~/bin
```

```yaml
# ~/.config/rufio/bookmarks.yml
- path: ~/Documents
  name: Documents
- path: ~/projects
  name: Projects
```

### プロジェクト設定

プロジェクトのルートに `rufio.yml` を置くと、そのプロジェクト用のスクリプトパスを追加できます。

```yaml
# ./rufio.yml
script_paths:
  - ./scripts
  - ./bin
```

## 外部ツール

すべて任意です。インストールしていなければ、その機能を無効にするか組み込みの動作に切り替えます。`rufio -c` で検出状況を確認できます。

| ツール | 用途 | キー |
|--------|------|------|
| fzf | ファイル名検索 | `s`、`/` |
| rga | ファイル内容検索 | `F` |
| zoxide | ディレクトリ履歴 | `z` |
| bat | プレビューのシンタックスハイライト | — |

```bash
# macOS
brew install fzf bat rga zoxide

# Ubuntu/Debian
apt install fzf bat zoxide
# rga: https://github.com/phiresky/ripgrep-all
```

## コマンドラインオプション

```bash
rufio [DIRECTORY]          # DIRECTORY で起動（省略時はカレントディレクトリ）
rufio -c                   # 依存関係をチェック（--check-health）
rufio --shell-init [SHELL] # rf シェル関数を出力
rufio --yjit               # YJIT を有効化（Ruby 3.1+）
rufio --zjit               # ZJIT を有効化（Ruby 3.4+）
rufio --native             # 実験的なネイティブディレクトリスキャナー
rufio --test               # FPS カウンターを表示
rufio -h                   # ヘルプ
```

## ネイティブエンジン

gem には macOS（arm64/x86_64）、Linux（x86_64/aarch64、glibc 2.17 以降または musl）、Windows（x64/arm64）向けの Zig ライブラリが同梱されています。その他のプラットフォームでは自動的に Ruby 実装を使います。

- **G モードの内容検索**: 並列スキャンとメモリ上のファイルキャッシュで、再検索は `rg` の約 10 倍速くなります。大文字・小文字のある非 ASCII 文字を含む検索語は Ruby で検索します。`RUFIO_NATIVE_SEARCH=0` で無効化できます。
- **ZIP**: エントリの伸長と 1 MiB 以上のファイルの圧縮を並列に行います（4 CPU・64 MB × 8 ファイルの計測で、Ruby より圧縮が約 4.6 倍、展開が約 3.2 倍高速）。アーカイブの検証は常に Ruby 側で行います。`RUFIO_NATIVE_ZIP=0` で無効化できます。

同梱バイナリの再ビルド（Zig 0.17 が必要）:

```bash
bundle exec rake native:build   # 全プラットフォーム
bundle exec rake native:check   # 同梱バイナリの検証
```
