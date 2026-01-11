# frozen_string_literal: true

module Rufio
  module Plugins
    # Hello コマンドを提供するプラグイン
    # Rubyコードで挨拶を返す簡単な例
    class Stop < Plugin
      def name
        'Stop'
      end

      def description
        'Rubyで実装された挨拶コマンドの例'
      end

      def commands
        {
          stop: method(:say_hello)
        }
      end

      private

      # 挨拶メッセージを返す
      def say_hello
        'stop 5seconds'
        sleep 5
        'done'
      end
    end
  end
end
