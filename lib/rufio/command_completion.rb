# frozen_string_literal: true

module Rufio
  # コマンド補完機能を提供するクラス
  class CommandCompletion
    # 初期化
    # @param history [CommandHistory, nil] コマンド履歴（オプション）
    # @param command_mode [CommandMode, nil] コマンドモード（スクリプト補完に使用）
    def initialize(history = nil, command_mode = nil)
      @command_mode = command_mode || CommandMode.new
      @shell_completion = ShellCommandCompletion.new
      @history = history
    end

    # コマンドの補完候補を取得
    # @param input [String] 入力されたテキスト
    # @return [Array<String>] 補完候補のリスト
    def complete(input)
      # 入力が空の場合は内部コマンド + スクリプト + rakeタスクを返す
      if input.nil? || input.strip.empty?
        return @command_mode.available_commands.map(&:to_s) +
               script_candidates('') +
               rake_candidates('')
      end

      # シェルコマンド補完（!で始まる場合）
      if input.strip.start_with?('!')
        return complete_shell_command(input.strip)
      end

      # スクリプト補完（@で始まる場合）
      if input.strip.start_with?('@')
        return @command_mode.complete_script(input.strip)
      end

      # rakeタスク補完（rake:で始まる場合）
      if input.strip.start_with?('rake:')
        prefix = input.strip[5..-1]
        return @command_mode.complete_rake_task(prefix)
      end

      # 通常のコマンド補完（内部コマンド + rakeタスク）
      available_commands = @command_mode.available_commands.map(&:to_s)
      input_lower = input.downcase
      candidates = available_commands.select do |command|
        command.downcase.start_with?(input_lower)
      end

      # rakeタスクも候補に追加（"r", "ra", "rak", "rake" 等にマッチ）
      rake_tasks = rake_candidates('')
      candidates += rake_tasks.select { |task| task.downcase.start_with?(input_lower) }

      candidates
    end

    # 補完候補の共通プレフィックスを取得
    # @param input [String] 入力されたテキスト
    # @return [String] 共通プレフィックス
    def common_prefix(input)
      candidates = complete(input)

      # 候補がない場合は元の入力を返す
      return input if candidates.empty?

      # 候補が1つの場合はそのコマンド名を返す
      return candidates.first if candidates.size == 1

      # 複数の候補がある場合、共通プレフィックスを計算
      min_candidate = candidates.min
      max_candidate = candidates.max

      min_candidate.chars.zip(max_candidate.chars).each_with_index do |(char_min, char_max), index|
        return min_candidate[0...index] if char_min != char_max
      end

      # すべての文字が一致した場合は最小の候補を返す
      min_candidate
    end

    private

    # スクリプト候補を取得（ScriptRunner + ローカルスクリプト）
    # @param prefix [String] 入力中の文字列
    # @return [Array<String>] スクリプト候補（@付き）
    def script_candidates(prefix)
      @command_mode.complete_script("@#{prefix}")
    end

    # rakeタスク候補を取得
    # @param prefix [String] 入力中の文字列
    # @return [Array<String>] rakeタスク候補（rake:付き）
    def rake_candidates(prefix)
      @command_mode.complete_rake_task(prefix)
    end

    # シェルコマンドの補完
    # @param input [String] ! で始まる入力
    # @return [Array<String>] 補完候補のリスト
    def complete_shell_command(input)
      # ! を除去
      command_part = input[1..-1]

      # スペースが含まれる場合、コマンドと引数に分離
      if command_part.include?(' ')
        parts = command_part.split(' ', 2)
        cmd = parts[0]
        arg = parts[1] || ''

        # 引数部分がパスっぽい場合、ファイルパス補完
        if arg.include?('/') || arg.start_with?('~')
          path_candidates = @shell_completion.complete_path(arg)
          return path_candidates.map { |path| "!#{cmd} #{path}" }
        else
          # 引数部分のファイル補完（カレントディレクトリ）
          path_candidates = @shell_completion.complete_path(arg)
          return path_candidates.map { |path| "!#{cmd} #{path}" }
        end
      else
        # コマンド名の補完
        cmd_candidates = @shell_completion.complete_command(command_part)

        # 履歴からの補完も追加
        if @history
          history_candidates = @shell_completion.complete_from_history(command_part, @history)
          cmd_candidates += history_candidates
        end

        # ! を付けて返す
        cmd_candidates.uniq.map { |cmd| "!#{cmd}" }
      end
    end
  end
end
