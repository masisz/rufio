# Rufio プラグインガイド

Rufioのプラグインシステムを使って、機能を拡張する方法を説明します。

## 目次

1. [プラグインの基本](#プラグインの基本)
2. [プラグインの作成](#プラグインの作成)
3. [プラグインの設定](#プラグインの設定)
4. [高度な機能](#高度な機能)
5. [トラブルシューティング](#トラブルシューティング)

## プラグインの基本

### プラグインとは？

プラグインは、Rufioに新しい機能を追加するためのRubyモジュールです。

### プラグインの種類

1. **組み込みプラグイン**: Rufio本体に含まれる
   - 場所: `lib/rufio/plugins/`
   - 例: `FileOperations`

2. **ユーザープラグイン**: ユーザーが作成する
   - 場所: `~/.rufio/plugins/`
   - 自由にカスタマイズ可能

## プラグインの作成

### ステップ1: ディレクトリの準備

```bash
# プラグインディレクトリを作成
mkdir -p ~/.rufio/plugins
```

### ステップ2: プラグインファイルの作成

`~/.rufio/plugins/my_plugin.rb`を作成：

```ruby
# frozen_string_literal: true

module Rufio
  module Plugins
    class MyPlugin < Plugin
      # プラグイン名（必須）
      def name
        "MyPlugin"
      end

      # 説明（オプション）
      def description
        "私のカスタムプラグイン"
      end

      # バージョン（オプション）
      def version
        "1.0.0"
      end

      # コマンドの定義（オプション）
      def commands
        {
          hello: method(:say_hello)
        }
      end

      private

      def say_hello
        puts "Hello from MyPlugin!"
      end
    end
  end
end
```

### ステップ3: プラグインの読み込み

Rufioを起動すると、自動的に`~/.rufio/plugins/`内のプラグインが読み込まれます。

## プラグインの設定

### 設定ファイルの作成

`~/.rufio/config.yml`:

```yaml
plugins:
  # プラグイン名を小文字で指定
  myplugin:
    enabled: true

  # 無効化したいプラグイン
  fileoperations:
    enabled: false
```

### 設定のルール

- **プラグイン名**: 大文字小文字を区別せず、小文字に統一されます
  - `MyPlugin`, `myplugin`, `MYPLUGIN` → すべて `myplugin` として扱われます
- **デフォルト**: 設定に記載のないプラグインは**有効**です
- **enabled**: `true`で有効、`false`で無効

## 高度な機能

### 外部gemへの依存

プラグインが外部gemに依存する場合、`requires`を使用：

```ruby
module Rufio
  module Plugins
    class AdvancedPlugin < Plugin
      # 依存するgemを宣言
      requires 'httparty', 'nokogiri'

      def name
        "AdvancedPlugin"
      end

      def description
        "HTTPartyとNokogiriを使用"
      end

      private

      def fetch_and_parse
        require 'httparty'
        require 'nokogiri'

        response = HTTParty.get('https://example.com')
        doc = Nokogiri::HTML(response.body)
        # 処理...
      end
    end
  end
end
```

gemが不足している場合、以下のメッセージが表示されます：

```
⚠️  Plugin 'AdvancedPlugin' は以下のgemに依存していますが、インストールされていません:
  - httparty
  - nokogiri

以下のコマンドでインストールしてください:
  gem install httparty nokogiri
```

### コマンドの定義

プラグインは複数のコマンドを提供できます：

```ruby
def commands
  {
    search: method(:search_files),
    count: method(:count_files),
    list: method(:list_files)
  }
end

private

def search_files
  # 検索処理
end

def count_files
  # カウント処理
end

def list_files
  # 一覧表示
end
```

## プラグインの例

### 1. ファイル検索プラグイン

```ruby
module Rufio
  module Plugins
    class FileSearchPlugin < Plugin
      def name
        "FileSearch"
      end

      def description
        "ファイル名で検索"
      end

      def commands
        {
          search: method(:search_files),
          find_ext: method(:find_by_extension)
        }
      end

      private

      def search_files(query = "*")
        Dir.glob("**/*#{query}*").each do |file|
          puts file if File.file?(file)
        end
      end

      def find_by_extension(ext)
        Dir.glob("**/*.#{ext}").each do |file|
          puts file
        end
      end
    end
  end
end
```

### 2. Git統合プラグイン

```ruby
module Rufio
  module Plugins
    class GitPlugin < Plugin
      def name
        "Git"
      end

      def description
        "Git操作の統合"
      end

      def commands
        {
          status: method(:git_status),
          branch: method(:current_branch),
          log: method(:git_log)
        }
      end

      private

      def git_status
        system('git status') if git_available?
      end

      def current_branch
        if git_available?
          branch = `git branch --show-current`.strip
          puts "ブランチ: #{branch}"
        end
      end

      def git_log
        system('git log --oneline -10') if git_available?
      end

      def git_available?
        if system('which git > /dev/null 2>&1')
          true
        else
          puts "⚠️  gitがインストールされていません"
          false
        end
      end
    end
  end
end
```

### 3. システム情報プラグイン

```ruby
module Rufio
  module Plugins
    class SystemInfoPlugin < Plugin
      def name
        "SystemInfo"
      end

      def description
        "システム情報を表示"
      end

      def commands
        {
          info: method(:show_system_info),
          disk: method(:show_disk_usage)
        }
      end

      private

      def show_system_info
        puts "OS: #{RbConfig::CONFIG['host_os']}"
        puts "Ruby: #{RUBY_VERSION}"
        puts "ホームディレクトリ: #{ENV['HOME']}"
      end

      def show_disk_usage
        puts "ディスク使用量:"
        system('df -h .')
      end
    end
  end
end
```

## プラグインの仕組み

### 自動登録

プラグインは`Rufio::Plugin`を継承すると、自動的に`PluginManager`に登録されます：

```ruby
class MyPlugin < Plugin
  # 継承した時点で自動登録される
end
```

### 初期化時の依存チェック

プラグインがインスタンス化されるとき、`requires`で宣言したgemがインストールされているかチェックされます：

```ruby
def initialize
  check_dependencies!  # 自動的に呼ばれる
end
```

## トラブルシューティング

### プラグインが読み込まれない

**症状**: プラグインを作成したのに動作しない

**確認事項**:
1. ファイルの場所: `~/.rufio/plugins/` に配置されているか
2. ファイル名: `.rb`拡張子がついているか
3. 構文エラー: Rubyの構文が正しいか
4. 設定ファイル: `config.yml`で無効化されていないか

### 依存gemが見つからない

**症状**: プラグイン起動時にエラーが出る

**解決方法**:
```bash
# エラーメッセージに表示されたgemをインストール
gem install <gem名>
```

### プラグインが無効化されている

**症状**: プラグインが読み込まれない（エラーなし）

**確認**: `~/.rufio/config.yml`を確認

```yaml
plugins:
  myplugin:
    enabled: false  # ← これを true に変更
```

## ベストプラクティス

### 1. わかりやすい名前をつける

```ruby
def name
  "MyAwesomePlugin"  # 明確で分かりやすい名前
end
```

### 2. 説明を書く

```ruby
def description
  "このプラグインは〇〇の機能を提供します"
end
```

### 3. エラーハンドリング

```ruby
def my_command
  # エラーが起きる可能性のある処理
  result = some_operation
rescue StandardError => e
  puts "⚠️  エラーが発生しました: #{e.message}"
end
```

### 4. 外部コマンドの確認

```ruby
def command_available?(cmd)
  system("which #{cmd} > /dev/null 2>&1")
end

def my_feature
  unless command_available?('git')
    puts "⚠️  gitがインストールされていません"
    return
  end

  # 処理...
end
```

## 参考

- サンプルプラグイン: `docs/plugin_example.rb`
- 組み込みプラグイン: `lib/rufio/plugins/file_operations.rb`
- プラグイン基底クラス: `lib/rufio/plugin.rb`
- プラグインマネージャー: `lib/rufio/plugin_manager.rb`

## まとめ

1. `~/.rufio/plugins/` にRubyファイルを作成
2. `Rufio::Plugin`を継承したクラスを定義
3. 必須メソッド`name`を実装
4. オプションで`description`、`version`、`commands`を実装
5. Rufio起動時に自動読み込み

プラグインシステムを使って、Rufioを自分好みにカスタマイズしてください！
