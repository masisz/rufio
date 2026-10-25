# rufio

**Runtime Unified Flow I/O Operator**

日々のスクリプト作業を手元にまとめるターミナルファイラ。
ファイルを探し、その場所で Ruby・Python・PowerShell を実行し、ジョブとログを確認できます。
自分用の操作は Ruby で追加できます。

**日本語** | [English](./README.md)

## rufioならではの点

rufio は、ファイルを探すところからスクリプトの実行、結果の確認までを一つの画面にまとめます。

- **ファイルのある場所からスクリプトを実行**: スクリプトのディレクトリを登録し、`:` → `@` + スクリプト名の一部 → `Tab` → `Enter` で呼び出せます。Ruby・Python・PowerShell を、いま開いているディレクトリで実行できます
- **ジョブとログで実行結果を追える**: バックグラウンドで実行しながらファイル操作を続け、`J` でジョブ、`L` で実行ログを確認できます
- **自分用の操作を Ruby で追加**: `~/.config/rufio/commands.rb` に小さな Ruby DSL で独自コマンドを定義できます。`~/.rufio/commands.rb` にも対応しています
- **インストール済みのツールと追加設定なしで連携**: fzf でファイル名検索、rga で内容検索、bat でプレビューのシンタックスハイライト、zoxide でディレクトリ履歴から移動できます
- **Windows にも対応**: PowerShell スクリプトの実行に対応し、Windows のターミナルに合わせたキー入力処理を備えています
- **挙動をソースで追いやすい**: Ruby を中心とした実装で、必要な処理を自分で確認・修正できます。セキュリティに関する設計は [SECURITY.md](./SECURITY.md) にまとめています

## 特徴

### スクリプト作業のために

- **マルチ言語スクリプト対応**: Ruby, Python, PowerShell
- **スクリプトパス管理**: 複数のスクリプトディレクトリを登録・管理
- **コマンド補完**: `@`プレフィックスでスクリプトをTab補完
- **ジョブ管理**: バックグラウンドでスクリプト/コマンドを実行
- **実行ログ**: すべての実行結果を自動記録

### ファイルマネージャーとして

- **Vimライクなキーバインド**: 直感的なナビゲーション
- **リアルタイムプレビュー**: ファイル内容を即座に表示（`bat` によるシンタックスハイライト対応）
- **高速検索**: fzf/rgaとの連携
- **ブックマーク**: よく使うディレクトリに素早くアクセス
- **zoxide連携**: スマートなディレクトリ履歴

### クロスプラットフォーム

- **macOS**: ネイティブサポート
- **Linux**: ネイティブサポート
- **Windows**: PowerShellスクリプト対応

## インストール

```bash
gem install rufio
```

または、Gemfileに追加:

```ruby
gem 'rufio'
```

## クイックスタート

### 1. 起動

```bash
rufio           # カレントディレクトリで起動
rufio /path/to  # 指定したディレクトリで起動
```

### 2. スクリプトパスを登録

1. スクリプトを配置したいディレクトリに移動
2. `B` → `2` でスクリプトパスに追加

### 3. スクリプトを実行

1. `:` でコマンドモードを起動
2. `@` + スクリプト名の一部を入力
3. `Tab` で補完
4. `Enter` で実行

## キーバインド

### 基本操作

| キー | 機能 |
|------|------|
| `j/k` | 上下移動 |
| `h/l` | 親/子ディレクトリ |
| `g/}` | 先頭/末尾 |
| `Enter` | ディレクトリに入る/ファイルを開く |
| `q` | 終了 |

### ファイル操作

| キー | 機能 |
|------|------|
| `Space` | 選択/選択解除 |
| `o` | 外部エディタで開く |
| `a/A` | ファイル/ディレクトリ作成 |
| `r` | リネーム |
| `d` | 削除 |
| `m/c/x` | 移動/コピー/削除（選択済み） |

### 検索・フィルター

| キー | 機能 |
|------|------|
| `f` | フィルターモード |
| `s` | fzfでファイル検索 |
| `F` | rgaでファイル内容検索 |

### ナビゲーション

| キー | 機能 |
|------|------|
| `b` | ブックマーク追加 |
| `B` | ブックマークメニュー |
| `0` | 起動ディレクトリに戻る |
| `1-9` | ブックマークにジャンプ |
| `Tab` | 次のブックマークへ循環移動（Filesモード限定） |
| `z` | zoxide履歴 |

### ツールランタイム

| キー | 機能 |
|------|------|
| `:` | コマンドモード |
| `J` | ジョブモード |
| `L` | 実行ログ表示 |
| `?` | ヘルプ |
| `G` | 全ブックマーク配下のファイル名・ファイル内容を横断検索 |
| `C` | ~/.config/rufio/を開く（Configモード、操作はFilesと共通） |
| `Shift+Tab` | モード切り替え（逆順） |

### Gモード（横断検索）

`G` を押すと、ブックマークした全ディレクトリの配下を再帰的に検索します。
Tabで **File names（ファイル名）** と **Content（ファイル内容）** を切り替えます。
大文字・小文字を区別しない文字列の部分一致で検索し、内容検索ではファイル名・行番号・一致した行を表示します。
テキストはUTF-8として読み込み、先頭8 KBにNULバイトがあるファイルはバイナリとしてスキップします。
上下矢印または `Ctrl+N/P` で選択、
Enterで選んだファイルの場所へ移動します。`Ctrl+U` で検索語をクリアし、
Escで元の表示に戻ります。検索はバックグラウンドで進みます。
検索対象は `b` で登録したブックマークです。外部検索ツールは不要です。
アクセスできないディレクトリはスキップし、ディレクトリのシンボリックリンクは辿りません。

ファイル名検索・内容検索から特定の拡張子を除外するには、
`~/.config/rufio/config.rb` に以下を追加してRufioを再起動します。

```ruby
GLOBAL_SEARCH_EXCLUDED_EXTENSIONS = %w[.png .jpg .zip .tar.gz .log].freeze
```

大文字・小文字は区別せず、先頭のドットは省略できます。デフォルトは `[]`（拡張子の除外なし）です。
ディレクトリ名には適用しません。

## コマンドモード

`:` でコマンドモードを起動し、様々なコマンドを実行できます。

### スクリプト実行

```
:@build           # @で始まるとスクリプト補完
:@deploy.rb       # 登録済みスクリプトを実行
```

### シェルコマンド

```
:!git status      # !で始まるとシェルコマンド
:!ls -la          # バックグラウンドで実行
```

### 組み込みコマンド

```
:hello            # 挨拶メッセージ
:stop             # rufioを終了
```

## スクリプトパス

### スクリプトパスとは

スクリプトファイルを配置するディレクトリを登録する機能です。登録したディレクトリ内のスクリプトは、コマンドモードで `@` プレフィックスを使って実行できます。

### 管理方法

`B` → `3` でスクリプトパス管理メニューを開きます：

- 登録済みパスの一覧表示
- `d`: パスを削除
- `Enter`: ディレクトリにジャンプ
- `ESC`: メニューを閉じる

### 対応スクリプト

| 拡張子 | 言語 |
|--------|------|
| `.rb` | Ruby |
| `.py` | Python |
| `.ps1` | PowerShell |
| `.sh` | Shell (bash/zsh) |

## DSLコマンド

`~/.config/rufio/commands.rb` でカスタムコマンドを定義できます：

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

## 設定

### 設定ファイル構成

```
~/.config/rufio/
├── config.rb         # メイン設定（スクリプトパス、カラー等）
├── commands.rb       # DSLコマンド定義
├── bookmarks.json    # ブックマーク
├── scripts/          # スクリプトファイル
└── logs/             # 実行ログ
```

### 設定例

```ruby
# ~/.config/rufio/config.rb

# スクリプトパス - スクリプトを配置するディレクトリ
SCRIPT_PATHS = [
  '~/.config/rufio/scripts',
  '~/my-scripts',
  './scripts'
].freeze

# カラー設定（HSL形式推奨）
COLORS = {
  directory: { hsl: [220, 80, 60] },
  file: { hsl: [0, 0, 90] },
  executable: { hsl: [120, 70, 50] },
  selected: { hsl: [50, 90, 70] },
  preview: { hsl: [180, 60, 65] }
}.freeze
```

### ローカル設定

プロジェクトルートに `rufio.rb` を配置すると、そのプロジェクト専用のスクリプトパスを設定できます：

```ruby
# ./rufio.rb（プロジェクトルート）
SCRIPT_PATHS = [
  './scripts',
  './bin'
].freeze
```

## 外部ツール連携

rufioは以下の外部ツールと連携して機能を拡張します。
すべて**オプション**です。インストールなしでも rufio は正常動作します。

| ツール | 用途 | キー | 必須 |
|--------|------|------|------|
| fzf | ファイル名検索 | `s` | オプション |
| rga | ファイル内容検索 | `F` | オプション |
| zoxide | ディレクトリ履歴 | `z` | オプション |
| bat | プレビューのシンタックスハイライト | — | オプション |

### bat — シンタックスハイライト

`bat` をインストールすると、プレビューペインでコードファイルを開いた際に
シンタックスハイライトが表示されます（Ruby、Python、Go、Rust、TypeScript など15言語以上対応）。

ハイライトはバックグラウンドで非同期に読み込まれるため、大きなソースツリーでも
カーソル移動が重くなりません。

```bash
# macOS
brew install bat

# Ubuntu/Debian
apt install bat
```

`rufio -c` を実行すると bat が正しく認識されているか確認できます。

### インストール（全ツール）

```bash
# macOS
brew install fzf bat rga zoxide

# Ubuntu/Debian
apt install fzf bat zoxide
# rgaは別途インストール: https://github.com/phiresky/ripgrep-all
```

## 高度な機能

### ネイティブスキャナー（実験的）

高速なディレクトリスキャンのためのネイティブ実装をサポート：

```bash
rufio --native        # 自動検出
rufio --native=zig    # Zig実装
```

### JITコンパイラ

```bash
rufio --yjit   # Ruby 3.1+ YJIT
rufio --zjit   # Ruby 3.4+ ZJIT
```

### ヘルスチェック

```bash
rufio -c              # システム依存関係をチェック
rufio --check-health  # 同上
```

## 開発

### 必要な環境

- Ruby 2.7.0以上
- io-console, pastel, tty-cursor, tty-screen gems

### 開発版の実行

```bash
git clone https://github.com/masisz/rufio
cd rufio
bundle install
./bin/rufio
```

### テスト

```bash
bundle exec rake test
```

## ライセンス

MIT License

## 貢献

バグ報告や機能リクエストは [GitHub Issues](https://github.com/masisz/rufio/issues) でお願いします。
プルリクエストも歓迎です！
