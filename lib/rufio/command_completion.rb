# frozen_string_literal: true

module Rufio
  # コマンド補完機能を提供するクラス
  class CommandCompletion
    # 初期化
    def initialize
      @command_mode = CommandMode.new
    end

    # コマンドの補完候補を取得
    # @param input [String] 入力されたテキスト
    # @return [Array<String>] 補完候補のリスト
    def complete(input)
      # 利用可能なコマンド名を文字列として取得
      available_commands = @command_mode.available_commands.map(&:to_s)

      # 入力が空の場合はすべてのコマンドを返す
      return available_commands if input.nil? || input.strip.empty?

      # 大文字小文字を区別せずに部分一致するコマンドを抽出
      input_lower = input.downcase
      candidates = available_commands.select do |command|
        command.downcase.start_with?(input_lower)
      end

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
  end
end
