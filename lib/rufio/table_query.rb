# frozen_string_literal: true

module Rufio
  # 表プレビューの `/` で入力する絞り込み条件。SQL を書かずに済む書き方で受け取り、
  # SQLite では WHERE 句へ、CSV / Excel では Ruby 側の判定へ同じ条件を渡す。
  #
  #   price > 100, name a%   →  price > 100 AND name LIKE 'a%'
  #   apple                  →  どれかの列に apple を含む
  #
  # 約束事:
  # - カンマで条件を区切る（引用符の中のカンマは区切らない）
  # - 先頭が列名（大文字小文字は無視）か列ラベル（A, B, ...）ならその列の条件
  # - 比較演算子（= != <> >= <= > <）があればそのまま、無ければ LIKE
  # - LIKE の値に % / _ が無ければ前後に % を付ける（部分一致）。引用符で囲めばそのまま
  # - 列を書かなければ全列の OR
  #
  # SQL は組み立てない（それは SqliteTableSource の仕事）。ここで持つのは条件だけで、
  # 列名は必ず実在する列の名前に解決してから渡す。
  class TableQuery
    # 入力が条件として読めなかったとき
    class Error < StandardError; end

    # @!attribute column
    #   @return [String, nil] 列名（nil なら全列）
    # @!attribute operator
    #   @return [String] 'LIKE' か比較演算子
    # @!attribute value
    #   @return [String] 比較する値（LIKE ならパターン）
    Condition = Struct.new(:column, :operator, :value, keyword_init: true)

    # 長いものから順に見る（>= を > と = に分けて読まないため）
    OPERATORS = ['>=', '<=', '!=', '<>', '=', '>', '<'].freeze
    LIKE = 'LIKE'
    WILDCARDS = ['%', '_'].freeze

    attr_reader :text, :conditions, :columns

    class << self
      # @param text [String, nil] 入力
      # @param columns [Array<String>] 表の列名（見出し行。無ければ空配列）
      # @return [TableQuery, nil] 空の入力なら nil
      def parse(text, columns)
        source = text.to_s
        return nil if source.strip.empty?

        names = Array(columns).map { |name| name.to_s }
        conditions = split_terms(source).map { |term| parse_term(term, names) }.compact
        return nil if conditions.empty?

        new(text: source.strip, conditions: conditions, columns: names)
      end

      private

      # カンマで分ける。引用符の中のカンマは区切りにしない
      def split_terms(text)
        terms = []
        current = +''
        quote = nil
        text.each_char do |char|
          if quote
            quote = nil if char == quote
            current << char
          elsif char == '"' || char == "'"
            quote = char
            current << char
          elsif char == ','
            terms << current
            current = +''
          else
            current << char
          end
        end
        terms << current
        terms.map(&:strip).reject(&:empty?)
      end

      def parse_term(term, columns)
        column, rest = split_column(term, columns)
        operator, value = split_operator(rest)
        raise Error, 'missing value after the operator' if value.strip.empty?

        # 引用符はカンマや空白を含む値をまとめるためのもので、照合の仕方は変えない
        literal = unquote(value.strip)
        if operator == LIKE && WILDCARDS.none? { |wildcard| literal.include?(wildcard) }
          literal = "%#{literal}%"
        end
        Condition.new(column: column, operator: operator, value: literal)
      end

      # 先頭が列名（または列ラベル）なら、その列と残りを返す。
      # 列が無ければ [nil, 項全体]（全列検索）
      def split_column(term, columns)
        candidates = column_candidates(columns)
        # 長い名前を先に試す（"name" と "name kana" のような列があっても取り違えない）
        candidates.sort_by { |name, _| -name.length }.each do |name, resolved|
          next unless term.downcase.start_with?(name)

          rest = term[name.length..].to_s
          # 列名の直後は空白か演算子でなければ列指定とみなさない（"apples" の "a" 等）
          next unless rest.empty? || rest.start_with?(' ', "\t") || OPERATORS.any? { |op| rest.start_with?(op) }

          return [resolved, rest]
        end
        [nil, term]
      end

      # 探す名前（小文字） => 実在する列名
      def column_candidates(columns)
        candidates = {}
        columns.each_with_index do |name, index|
          label = column_label(index)
          candidates[label.downcase] = name.to_s.empty? ? label : name
          next if name.to_s.empty?

          candidates[name.downcase] = name
        end
        candidates
      end

      # A, B, ... Z, AA（TableSheet#column_label と同じ規則）
      def column_label(index)
        label = +''
        number = index
        loop do
          label = ((number % 26) + 65).chr + label
          number = number / 26 - 1
          break if number.negative?
        end
        label
      end

      def split_operator(rest)
        text = rest.to_s.strip
        operator = OPERATORS.find { |candidate| text.start_with?(candidate) }
        return [LIKE, text] unless operator

        [operator, text[operator.length..].to_s]
      end

      # 両端の引用符を外す
      def unquote(value)
        %w[" '].each do |quote|
          return value[1..-2].to_s if value.length >= 2 && value.start_with?(quote) && value.end_with?(quote)
        end
        value
      end
    end

    def initialize(text:, conditions:, columns:)
      @text = text
      @conditions = conditions
      @columns = columns
    end

    def to_s
      @text
    end

    # CSV / Excel のための判定。すべての条件を満たす行だけを通す
    # @param row [Array<String>] 1 行
    # @param columns [Array<String>] 列名（見出し行）
    def matches?(row, columns = @columns)
      cells = Array(row)
      @conditions.all? { |condition| condition_matches?(condition, cells, Array(columns)) }
    end

    private

    def condition_matches?(condition, cells, columns)
      return any_column_matches?(condition, cells) if condition.column.nil?

      index = columns.index(condition.column)
      return false if index.nil?

      cell_matches?(condition, cells[index])
    end

    def any_column_matches?(condition, cells)
      cells.any? { |cell| cell_matches?(condition, cell) }
    end

    def cell_matches?(condition, cell)
      return false if cell.nil?

      text = cell.to_s
      return like?(text, condition.value) if condition.operator == LIKE

      compare(text, condition.value, condition.operator)
    end

    # SQLite の LIKE と同じく、% は 0 文字以上、_ は 1 文字、大文字小文字は無視する
    def like?(text, pattern)
      Regexp.new("\\A#{like_pattern(pattern)}\\z", Regexp::IGNORECASE).match?(text)
    end

    def like_pattern(pattern)
      pattern.each_char.map do |char|
        case char
        when '%' then '.*'
        when '_' then '.'
        else Regexp.escape(char)
        end
      end.join
    end

    # 両方が数値として読めれば数値で比べ、そうでなければ文字列で比べる
    # （"80" と "100" を文字列で比べると大小が逆になる）
    def compare(text, value, operator)
      left = numeric(text)
      right = numeric(value)
      if left && right
        apply(left, right, operator)
      else
        apply(text.downcase, value.downcase, operator)
      end
    end

    def apply(left, right, operator)
      case operator
      when '=' then left == right
      when '!=', '<>' then left != right
      when '>' then (left <=> right) == 1
      when '<' then (left <=> right) == -1
      when '>=' then (left <=> right) >= 0
      when '<=' then (left <=> right) <= 0
      else false
      end
    end

    def numeric(text)
      value = text.to_s.strip
      return nil if value.empty?

      Float(value)
    rescue ArgumentError, TypeError
      nil
    end
  end
end
