# frozen_string_literal: true

module Rufio
  # ANSI エスケープコード付きの行をトークン列に分解するモジュール。
  # bat --color=always の出力をシンタックスハイライト表示するために使用する。
  module AnsiLineParser
    # SGR (Select Graphic Rendition) ANSI エスケープシーケンスにマッチするパターン
    ANSI_SGR_PATTERN = /\e\[[0-9;]*m/

    # ANSI 付き行を {text: String, fg: String|nil} のトークン配列に分解する。
    #
    # @param line [String] ANSI コードを含む可能性がある行
    # @return [Array<Hash>] {text:, fg:} のトークン配列
    def self.parse(line)
      tokens = []
      current_fg = nil

      # ANSI SGR シーケンス、非エスケープ文字列、孤立エスケープの順にスキャン
      line.scan(/#{ANSI_SGR_PATTERN}|[^\e]+|\e(?!\[)/) do |part|
        if part.start_with?("\e[")
          current_fg = apply_ansi_sequence(current_fg, part)
        else
          tokens << { text: part, fg: current_fg }
        end
      end

      tokens
    end

    # トークン配列の表示幅（ANSI コードを除く）を計算する。
    #
    # @param tokens [Array<Hash>] parse が返したトークン配列
    # @return [Integer] 表示幅
    def self.display_width(tokens)
      tokens.sum { |t| TextUtils.display_width(t[:text]) }
    end

    # トークン配列を max_width で折り返し、行ごとのトークン配列の配列を返す。
    # 全角文字（日本語等）は幅2として扱う。
    #
    # @param tokens [Array<Hash>] parse が返したトークン配列
    # @param max_width [Integer] 折り返し幅（表示幅基準）
    # @return [Array<Array<Hash>>] 行ごとのトークン配列
    def self.wrap(tokens, max_width)
      return [] if tokens.empty? || max_width <= 0

      lines = []
      current_line = []
      current_width = 0

      tokens.each do |token|
        fg = token[:fg]
        current_text = String.new

        token[:text].each_char do |char|
          char_w = TextUtils.char_width(char)

          if current_width + char_w > max_width
            # 折り返し: 現在のテキストをトークンとして確定
            current_line << { text: current_text, fg: fg } unless current_text.empty?
            lines << current_line
            current_line = []
            current_text = String.new
            current_width = 0
          end

          current_text << char
          current_width += char_w
        end

        current_line << { text: current_text, fg: fg } unless current_text.empty?
      end

      lines << current_line unless current_line.empty?
      lines
    end

    # private helper: ANSI シーケンスを適用して新しい fg 状態を返す。
    # リセットシーケンスは nil を返す。
    # 複合シーケンス（例: \e[0;32m）はリセット後の色だけを返す。
    def self.apply_ansi_sequence(current_fg, seq)
      # \e[ と m の間のコード文字列を取り出す
      codes_str = seq[2..-2]
      codes = codes_str.split(';')

      # すべてのコードがリセット（"0" or ""）ならリセット
      if codes.empty? || codes.all? { |c| c.empty? || c == '0' }
        return nil
      end

      # 先頭がリセットコードで後続に色指定がある場合（例: \e[0;32m）
      if codes.first.empty? || codes.first == '0'
        remaining = codes.drop_while { |c| c.empty? || c == '0' }
        return remaining.empty? ? nil : "\e[#{remaining.join(';')}m"
      end

      # 通常の色/属性コード → そのまま使用
      seq
    end

    private_class_method :apply_ansi_sequence
  end
end
