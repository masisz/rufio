# frozen_string_literal: true

module Rufio
  # DSL設定ファイルを読み込んでDslCommandを生成するクラス
  class DslCommandLoader
    attr_reader :errors, :warnings

    def initialize
      @errors = []
      @warnings = []
    end

    # 文字列からDSLを解析してコマンドをロードする
    # @param dsl_string [String] DSL文字列
    # @return [Array<DslCommand>] 有効なコマンドの配列
    def load_from_string(dsl_string)
      @errors = []
      @warnings = []

      context = DslContext.new
      begin
        context.instance_eval(dsl_string)
      rescue SyntaxError, StandardError => e
        @errors << "DSL parse error: #{e.message}"
        return []
      end

      validate_commands(context.commands)
    end

    # ファイルからDSLをロードする
    # @param file_path [String] 設定ファイルのパス
    # @return [Array<DslCommand>] 有効なコマンドの配列
    def load_from_file(file_path)
      @errors = []
      @warnings = []

      expanded_path = File.expand_path(file_path)
      unless File.exist?(expanded_path)
        return []
      end

      content = File.read(expanded_path)
      load_from_string(content)
    end

    # 複数のパスからDSLをロードする
    # @param paths [Array<String>] 設定ファイルのパス配列
    # @return [Array<DslCommand>] 有効なコマンドの配列
    def load_from_paths(paths)
      commands = []

      paths.each do |path|
        commands.concat(load_from_file(path))
      end

      commands
    end

    # デフォルトのパスからDSLをロードする
    # @return [Array<DslCommand>] 有効なコマンドの配列
    def load
      load_from_paths(default_config_paths)
    end

    # デフォルトの設定ファイルパスを返す
    # @return [Array<String>] 設定ファイルパスの配列
    def default_config_paths
      home = Dir.home
      [
        File.join(home, ".rufio", "commands.rb"),
        File.join(home, ".config", "rufio", "commands.rb")
      ]
    end

    private

    # コマンドをバリデーションし、有効なもののみを返す
    # @param commands [Array<DslCommand>] コマンドの配列
    # @return [Array<DslCommand>] 有効なコマンドの配列
    def validate_commands(commands)
      valid_commands = []

      commands.each do |cmd|
        if cmd.valid?
          valid_commands << cmd
        else
          @warnings << "Command '#{cmd.name}' is invalid: #{cmd.errors.join(', ')}"
        end
      end

      valid_commands
    end

    # DSL評価用の独立したコンテキスト
    class DslContext < BasicObject
      attr_reader :commands

      def initialize
        @commands = []
      end

      # コマンドを定義する
      # @param name [String] コマンド名
      # @yield コマンドの設定ブロック
      def command(name, &block)
        builder = CommandBuilder.new(name)
        builder.instance_eval(&block) if block
        @commands << builder.build
      end

      # 安全でないメソッドをブロック
      def method_missing(method_name, *_args)
        ::Kernel.raise ::NoMethodError, "Method '#{method_name}' is not allowed in DSL"
      end

      def respond_to_missing?(_method_name, _include_private = false)
        false
      end
    end

    # コマンドビルダー
    class CommandBuilder
      def initialize(name)
        @name = name
        @script = nil
        @description = ""
        @interpreter = nil
        @ruby_block = nil
        @shell_command = nil
      end

      def script(path)
        @script = path
      end

      def description(desc)
        @description = desc
      end

      def interpreter(interp)
        @interpreter = interp
      end

      # inline Rubyブロックを定義
      def ruby(&block)
        @ruby_block = block
      end

      # inline シェルコマンドを定義
      def shell(command)
        @shell_command = command
      end

      def build
        DslCommand.new(
          name: @name,
          script: @script,
          description: @description,
          interpreter: @interpreter,
          ruby_block: @ruby_block,
          shell_command: @shell_command
        )
      end

      # 未知のメソッドは無視
      def method_missing(_method_name, *_args)
        # DSL内で未知のメソッドが呼ばれた場合は無視
        nil
      end

      def respond_to_missing?(_method_name, _include_private = false)
        true
      end
    end
  end
end
