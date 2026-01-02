# frozen_string_literal: true

module Rufio
  module Plugins
    # Hello コマンドを提供するプラグイン
    # Rubyコードで挨拶を返す簡単な例
    class Hello < Plugin
      def name
        "Hello"
      end

      def description
        "Rubyで実装された挨拶コマンドの例"
      end

      def commands
        {
          hello: method(:say_hello)
        }
      end

      private

      # 挨拶メッセージを返す
      def say_hello
        "Hello, World! 🌍\n\nこのコマンドはRubyで実装されています。"
      end
    end
  end
end
