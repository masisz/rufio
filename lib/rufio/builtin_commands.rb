# frozen_string_literal: true

module Rufio
  # 組み込みコマンドを定義するモジュール
  # DSL形式で定義されたコマンドをDslCommandインスタンスとして提供する
  module BuiltinCommands
    class << self
      # 組み込みコマンドをロードする
      # @return [Hash{Symbol => DslCommand}] コマンド名をキーとしたハッシュ
      def load
        commands = {}

        # hello コマンド
        commands[:hello] = DslCommand.new(
          name: "hello",
          ruby_block: -> { "Hello, World!\n\nこのコマンドはDSLで定義されています。" },
          description: "挨拶メッセージを返す"
        )

        # stop コマンド
        commands[:stop] = DslCommand.new(
          name: "stop",
          ruby_block: lambda {
            sleep 5
            "done"
          },
          description: "5秒待機してdoneを返す"
        )

        commands
      end
    end
  end
end
