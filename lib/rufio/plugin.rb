# frozen_string_literal: true

module Rufio
  # プラグインを格納するモジュール
  module Plugins
  end

  # プラグインの基底クラス
  class Plugin
    # 依存gemが不足している場合に投げられるエラー
    class DependencyError < StandardError; end

    class << self
      # 継承時に自動的にPluginManagerに登録する
      def inherited(subclass)
        super
        PluginManager.register(subclass)
      end

      # 依存gemを宣言する
      def requires(*gems)
        @required_gems ||= []
        @required_gems.concat(gems)
      end

      # 宣言された依存gemのリストを取得する
      def required_gems
        @required_gems || []
      end
    end

    # 初期化時に依存gemをチェックする
    def initialize
      check_dependencies!
    end

    # プラグイン名（必須オーバーライド）
    def name
      raise NotImplementedError, "#{self.class}#name must be implemented"
    end

    # プラグインの説明（オプション）
    def description
      ""
    end

    # プラグインのバージョン（オプション）
    def version
      "1.0.0"
    end

    # コマンド定義（オプション）
    # { command_name: method(:method_name) } の形式で返す
    def commands
      {}
    end

    private

    # 依存gemが全て利用可能かチェックする
    def check_dependencies!
      required_gems = self.class.required_gems
      return if required_gems.empty?

      missing_gems = []

      required_gems.each do |gem_name|
        begin
          Gem::Specification.find_by_name(gem_name)
        rescue Gem::LoadError
          missing_gems << gem_name
        end
      end

      return if missing_gems.empty?

      # 不足しているgemがある場合はエラーを投げる
      error_message = <<~ERROR
        Plugin '#{name}' は以下のgemに依存していますが、インストールされていません:
          - #{missing_gems.join("\n  - ")}

        以下のコマンドでインストールしてください:
          gem install #{missing_gems.join(' ')}
      ERROR

      raise DependencyError, error_message
    end
  end
end
