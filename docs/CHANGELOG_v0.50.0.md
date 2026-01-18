# CHANGELOG v0.50.0

## 概要

DSLコマンドシステムへの完全移行を完了し、旧Pluginシステムを廃止しました。

## 重要な変更

### DSLコマンドシステムへの統一

- **Pluginシステムの廃止**: 旧来のPluginベースのコマンドシステムを完全に削除
- **DSLコマンドへの一本化**: すべてのコマンドがDSLベースで定義可能に
- **組み込みコマンドのDSL化**: `hello`, `stop`, `touch`, `mkdir` などがDSLコマンドとして実装

### 削除されたファイル

#### ライブラリ
- `lib/rufio/plugin.rb`
- `lib/rufio/plugin_manager.rb`
- `lib/rufio/plugin_config.rb`
- `lib/rufio/plugins/` ディレクトリ

#### テスト
- `test/test_plugin.rb`
- `test/test_plugin_config.rb`
- `test/test_plugin_manager.rb`
- `test/test_plugins_hello.rb`
- `test/test_plugins_file_operations.rb`

### 新しいDSLコマンドシステム

#### コマンド定義ファイル

```ruby
# ~/.config/rufio/commands.rb
command "hello" do
  ruby { "Hello from rufio!" }
  description "挨拶コマンド"
end

command "greet" do
  shell "echo 'Hello, World!'"
  description "シェルコマンドで挨拶"
end

command "build" do
  script "~/.config/rufio/scripts/build.rb"
  description "プロジェクトをビルド"
end
```

#### DSLコマンドの種類

1. **ruby**: Rubyコードをインラインで実行
2. **shell**: シェルコマンドを実行
3. **script**: 外部スクリプトファイルを実行

#### 組み込みコマンド

以下のコマンドがデフォルトで利用可能:

- `hello` - 挨拶メッセージを表示
- `stop` - rufioを終了
- `touch` - ファイルを作成
- `mkdir` - ディレクトリを作成

### 移行ガイド

#### 旧Pluginからの移行

**旧Plugin形式:**
```ruby
module Rufio
  module Plugins
    class Hello < Plugin
      def commands
        { hello: method(:say_hello) }
      end

      def say_hello
        "Hello from rufio!"
      end
    end
  end
end
```

**新DSL形式:**
```ruby
# ~/.config/rufio/commands.rb
command "hello" do
  ruby { "Hello from rufio!" }
  description "挨拶コマンド"
end
```

### 破壊的変更

- `Rufio::Plugin` クラスは削除されました
- `Rufio::PluginManager` クラスは削除されました
- `Rufio::PluginConfig` クラスは削除されました
- `~/.rufio/plugins/` ディレクトリのプラグインは読み込まれなくなりました
- `~/.rufio/config.yml` のplugins設定は無視されます

### 設定ファイルの変更

#### 新しい設定ファイル構成

```
~/.config/rufio/
├── config.rb         # カラー設定
├── commands.rb       # DSLコマンド定義（新規）
├── bookmarks.json    # ブックマーク
├── scripts/          # スクリプトファイル
└── log/              # 実行ログ
```

## テスト

全105テストがパス:
- `test_dsl_command.rb` - 14 tests
- `test_dsl_command_loader.rb` - 13 tests
- `test_dsl_command_inline.rb` - 18 tests
- `test_builtin_commands.rb` - 10 tests
- `test_command_mode.rb` - 19 tests
- `test_command_mode_unified.rb` - 11 tests
- `test_script_executor.rb` - 12 tests
- `test_dsl_integration.rb` - 8 tests
