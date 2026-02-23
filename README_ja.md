# rufio

**Runtime Unified Flow I/O Operator**

ファイルを起点に、ツールとスクリプトを実行・連携させるTUIファイルマネージャー。
Ruby/Python/PowerShellに対応し、開発ワークフローを一箇所に統合します。

A TUI file manager as a unified runtime environment for tools and scripts.

**日本語** | [English](./README.md)

## コンセプト

rufioは単なるファイルマネージャーではありません。**ツールランタイム実行環境**です。

```
┌─────────────────────────────────────────────────────────┐
│                        rufio                            │
│         Runtime Unified Flow I/O Operator               │
├─────────────────────────────────────────────────────────┤
│  Files ──→ Scripts ──→ Tools ──→ Output                 │
│    ↑                                   │                │
│    └───────────── Feedback ────────────┘                │
└─────────────────────────────────────────────────────────┘
```

- **ファイル操作**: 従来のファイルマネージャー機能
- **スクリプト実行**: Ruby/Python/PowerShellスクリプトをファイルコンテキストで実行
- **ツール連携**: 外部ツール（git, fzf, rga等）とのシームレスな統合
- **統一I/O**: すべての入出力を単一のフローで管理

## 特徴

### ツールランタイムとして

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
| `g/G` | 先頭/末尾 |
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
| `Shift+Tab` | モード切り替え（逆順） |

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
