# frozen_string_literal: true

module Rufio
  # DSLで定義されたコマンドを表すクラス
  class DslCommand
    attr_reader :name, :script, :description, :interpreter, :errors

    # コマンドを初期化する
    # @param name [String] コマンド名
    # @param script [String] スクリプトパス
    # @param description [String] コマンドの説明
    # @param interpreter [String, nil] インタープリタ（nilの場合は自動検出）
    def initialize(name:, script:, description: "", interpreter: nil)
      @name = name.to_s
      @script = normalize_path(script.to_s)
      @description = description.to_s
      @interpreter = interpreter || auto_resolve_interpreter
      @errors = []
    end

    # コマンドが有効かどうかを検証する
    # @return [Boolean]
    def valid?
      @errors = []
      validate_name
      validate_script
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
      {
        name: @name,
        script: @script,
        description: @description,
        interpreter: @interpreter
      }
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
      return nil if @script.empty?

      InterpreterResolver.resolve_from_path(@script)
    end

    # コマンド名のバリデーション
    def validate_name
      if @name.empty?
        @errors << "Command name is required"
      end
    end

    # スクリプトパスのバリデーション
    def validate_script
      if @script.empty?
        @errors << "Script path is required"
        return
      end

      unless File.exist?(@script)
        @errors << "Script not found: #{@script}"
      end
    end
  end
end
