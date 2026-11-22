# frozen_string_literal: true

module Rufio
  # プレビューモードの `/` で出す 1 行の入力欄。
  #
  # 文字の編集だけを担い、検索の実行も表示もしない。利用側（PreviewView の各種別）は
  # handle_key の戻り値で「入力が変わった / 確定した / 取り消した」を判断する。
  class SearchPrompt
    # 入力を取り消す／確定するキー
    CANCEL = "\e"
    SUBMIT = ["\r", "\n"].freeze
    BACKSPACE = ["\u007F", "\b"].freeze
    CLEAR = "\x15" # Ctrl+U

    attr_reader :query

    def initialize(query = '')
      @query = query.to_s.dup
    end

    # @return [Symbol] :changed（入力が変わった）/ :submitted / :cancelled / :ignored
    def handle_key(key)
      return :submitted if SUBMIT.include?(key)
      return :cancelled if key == CANCEL

      if BACKSPACE.include?(key)
        @query = @query[0...-1] || ''
        return :changed
      end

      if key == CLEAR
        @query = ''
        return :changed
      end

      return :ignored unless printable?(key)

      @query += key
      :changed
    end

    private

    # 制御文字・エスケープシーケンスは入力に混ぜない（検索画面と同じ判定）
    def printable?(key)
      key.is_a?(String) && !key.empty? && key.valid_encoding? &&
        key.each_codepoint.all? { |code| code >= 32 && code != 127 }
    end
  end
end
