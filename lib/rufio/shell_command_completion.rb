# frozen_string_literal: true

module Rufio
  # シェルコマンド補完機能を提供するクラス
  class ShellCommandCompletion
    # PATHからコマンドを補完
    # @param input [String] 入力されたコマンドの一部
    # @return [Array<String>] 補完候補のリスト
    def complete_command(input)
      return [] if input.nil? || input.empty?

      input_lower = input.downcase
      path_commands.select { |cmd| cmd.downcase.start_with?(input_lower) }
    end

    # ファイルパスを補完
    # @param input [String] 入力されたパスの一部
    # @param options [Hash] オプション
    # @option options [Boolean] :directories_only ディレクトリのみを補完
    # @return [Array<String>] 補完候補のリスト
    def complete_path(input, options = {})
      return [] if input.nil?

      # ~を展開
      expanded_input = File.expand_path(input) rescue input

      # 入力が/で終わる場合（ディレクトリ内を補完）
      if input.end_with?("/")
        dir = expanded_input
        pattern = File.join(dir, "*")
      else
        # ディレクトリ部分とファイル名部分を分離
        dir = File.dirname(expanded_input)
        basename = File.basename(expanded_input)
        pattern = File.join(dir, "#{basename}*")
      end

      # ディレクトリが存在しない場合は空の配列を返す
      return [] unless Dir.exist?(dir)

      # マッチするファイル/ディレクトリを取得
      candidates = Dir.glob(pattern)

      # ディレクトリのみのフィルタリング
      if options[:directories_only]
        candidates.select! { |path| File.directory?(path) }
      end

      # 元の入力が~で始まる場合、結果も~で始まるように変換
      if input.start_with?("~")
        home = ENV['HOME']
        candidates.map! { |path| path.sub(home, "~") }
      end

      candidates.sort
    rescue StandardError
      []
    end

    # コマンド履歴から補完
    # @param input [String] 入力されたコマンドの一部
    # @param history [CommandHistory] コマンド履歴オブジェクト
    # @return [Array<String>] 補完候補のリスト
    def complete_from_history(input, history)
      return [] if input.nil? || input.empty?
      return [] unless history

      # 履歴から全てのコマンドを取得
      # CommandHistoryクラスから履歴を取得する方法が必要
      # 現在の実装では、@historyインスタンス変数にアクセスできないため、
      # 新しいメソッドを追加する必要がある
      # 一旦、空の配列を返す実装にして、後でCommandHistoryを拡張する
      commands = get_history_commands(history)

      input_lower = input.downcase
      commands.select { |cmd| cmd.downcase.start_with?(input_lower) }.uniq
    end

    private

    # PATHから実行可能なコマンドのリストを取得
    # @return [Array<String>] コマンドのリスト
    def path_commands
      @path_commands ||= begin
        paths = ENV['PATH'].split(File::PATH_SEPARATOR)
        commands = []

        paths.each do |path|
          next unless Dir.exist?(path)

          Dir.foreach(path) do |file|
            next if file == '.' || file == '..'

            filepath = File.join(path, file)
            # 実行可能なファイルのみを追加
            commands << file if File.executable?(filepath) && !File.directory?(filepath)
          end
        end

        commands.uniq.sort
      rescue StandardError
        []
      end
    end

    # CommandHistoryオブジェクトからコマンドリストを取得
    # @param history [CommandHistory] 履歴オブジェクト
    # @return [Array<String>] コマンドのリスト
    def get_history_commands(history)
      # CommandHistoryの内部データにアクセスするため、
      # instance_variable_getを使用（本来はpublicメソッドを追加すべき）
      history_array = history.instance_variable_get(:@history) || []

      # ! を除去したコマンドを返す
      history_array.map do |cmd|
        cmd.start_with?('!') ? cmd[1..-1] : cmd
      end
    end
  end
end
