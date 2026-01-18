# frozen_string_literal: true

module Rufio
  # DSLで定義されたコマンドを表すクラス
  class DslCommand
    attr_reader :name, :script, :description, :interpreter, :errors
    attr_reader :ruby_block, :shell_command

    # コマンドを初期化する
    # @param name [String] コマンド名
    # @param script [String, nil] スクリプトパス
    # @param description [String] コマンドの説明
    # @param interpreter [String, nil] インタープリタ（nilの場合は自動検出）
    # @param ruby_block [Proc, nil] inline Rubyブロック
    # @param shell_command [String, nil] inline シェルコマンド
    def initialize(name:, script: nil, description: "", interpreter: nil,
                   ruby_block: nil, shell_command: nil)
      @name = name.to_s
      @script = script ? normalize_path(script.to_s) : nil
      @description = description.to_s
      @interpreter = interpreter || auto_resolve_interpreter
      @ruby_block = ruby_block
      @shell_command = shell_command
      @errors = []
    end

    # コマンドタイプを返す
    # @return [Symbol] :ruby, :shell, :script のいずれか
    def command_type
      if @ruby_block
        :ruby
      elsif @shell_command
        :shell
      else
        :script
      end
    end

    # コマンドが有効かどうかを検証する
    # @return [Boolean]
    def valid?
      @errors = []
      validate_name
      validate_execution_source
      @errors.empty?
    end

    # 実行用の引数配列を返す
    # @return [Array<String>] [インタープリタ, スクリプトパス]
    def to_execution_args
      [@interpreter, @script]
    end

    # ハッシュ表現を返す
    # @return [Hash]
    def to_h
      hash = {
        name: @name,
        script: @script,
        description: @description,
        interpreter: @interpreter
      }
      hash[:has_ruby_block] = true if @ruby_block
      hash[:shell_command] = @shell_command if @shell_command
      hash
    end

    private

    # パスを正規化する（チルダ展開、パストラバーサル解決）
    # @param path [String] 入力パス
    # @return [String] 正規化されたパス
    def normalize_path(path)
      return "" if path.empty?

      # チルダを展開
      expanded = File.expand_path(path)

      # ファイルが存在する場合は実際のパスを取得（パストラバーサル解決）
      if File.exist?(expanded)
        File.realpath(expanded)
      else
        # ファイルが存在しない場合は展開されたパスをそのまま返す
        expanded
      end
    end

    # 拡張子からインタープリタを自動検出する
    # @return [String, nil]
    def auto_resolve_interpreter
      return nil if @script.nil? || @script.empty?

      InterpreterResolver.resolve_from_path(@script)
    end

    # コマンド名のバリデーション
    def validate_name
      if @name.empty?
        @errors << "Command name is required"
      end
    end

    # 実行ソースのバリデーション
    # ruby_block, shell_command, script のいずれかが必要
    def validate_execution_source
      # ruby_block または shell_command がある場合はスクリプト不要
      return if @ruby_block || @shell_command

      # スクリプトパスのバリデーション
      if @script.nil? || @script.empty?
        @errors << "Script path is required"
        return
      end

      unless File.exist?(@script)
        @errors << "Script not found: #{@script}"
      end
    end
  end
end
