# frozen_string_literal: true

module Rufio
  # 候補のまとまりを Ruby の行（Hash）にせず、表示名を NUL で終端して連結した 1 本のバイト列で持つ。
  # FuzzySearchSession はこのバイト列をそのままインデックスに登録し、上位の結果になった候補だけ
  # entry(index) で行を作る。ソースは each_batch で行の配列の代わりにこのブロックを渡せる。
  #
  # ブロックは作成後に変わらないので、セッションとキャッシュが同じものを共有できる。
  # rows は (index, text) から行を作る呼び出し可能オブジェクトで、同じ引数には同じ内容を返すこと。
  class FuzzyCandidateBlock
    include Enumerable

    SEPARATOR = "\0".b.freeze
    MAX_TEXT_BYTES = 65_536
    TEXT_ROW = ->(_index, text) { { text: text } }

    attr_reader :packed, :size

    # 表示名を 1 件ずつ詰めてブロックを作る
    class Builder
      attr_reader :size

      def initialize
        @buffer = +''.b
        @size = 0
      end

      def empty?
        @size.zero?
      end

      # text は NUL を含まない正しい UTF-8（バイト列として渡してもよい）。追加した候補の番号を返す
      def add(text)
        raise ArgumentError, 'Candidate text too long' if text.bytesize > MAX_TEXT_BYTES

        @buffer << text << SEPARATOR
        @size += 1
        @size - 1
      end

      def build(rows = nil)
        FuzzyCandidateBlock.new(@buffer, @size, rows: rows, checked: true)
      end
    end

    # 「接頭辞 + 表示名」がそのままパスになるファイル候補の行 { text:, path: } を作る。
    # 表示名を scrub した等でパスを組み立て直せない候補だけ、exceptions に元のパスを持つ。
    class PathRows
      def initialize(prefix, encoding, exceptions = nil)
        @prefix = prefix
        @encoding = encoding
        @exceptions = exceptions
        freeze
      end

      def call(index, text)
        path = @exceptions && @exceptions[index]
        { text: text, path: path || (@prefix + text.b).force_encoding(@encoding).freeze }
      end
    end

    # packed: 「表示名 NUL」を size 件連結したもの。checked: true は Builder が詰めた（確認済みの）場合だけ指定する
    def initialize(packed, size, rows: nil, checked: false)
      raise ArgumentError, 'Expected packed candidate text' unless packed.is_a?(String) && size.is_a?(Integer)

      @packed = packed.frozen? && packed.encoding == Encoding::BINARY ? packed : packed.b.freeze
      @size = size
      @rows = rows || TEXT_ROW
      @offsets = nil
      return if checked

      unless @packed.count(SEPARATOR) == size && (size.zero? ? @packed.empty? : @packed.end_with?(SEPARATOR)) &&
             @packed.dup.force_encoding(Encoding::UTF_8).valid_encoding?
        raise ArgumentError, 'Invalid packed candidate text'
      end
    end

    def empty?
      @size.zero?
    end

    alias length size

    def text(index)
      raise IndexError, "index #{index} outside of candidate block" unless index.is_a?(Integer) && index >= 0 && index < @size

      start = offsets[index]
      finish = index + 1 < @size ? offsets[index + 1] : @packed.bytesize
      @packed.byteslice(start, finish - start - 1).force_encoding(Encoding::UTF_8).freeze
    end

    # 凍結した行（文字列も凍結）を返す。呼ぶたびに作るので、必要な候補だけに使う
    def entry(index)
      row = @rows.call(index, text(index))
      row.each_value { |value| value.freeze if value.is_a?(String) }
      row.freeze
    end

    def texts
      list = @packed.split(SEPARATOR, -1)
      list.pop
      list.each { |item| item.force_encoding(Encoding::UTF_8).freeze }
    end

    # 全件の行を作る（テストや、行の配列しか扱えない利用者向け）
    def each
      return enum_for(:each) { @size } unless block_given?

      @size.times { |index| yield entry(index) }
      self
    end

    alias to_ary to_a

    private

    # 各表示名の開始バイト位置。結果に出す候補が初めて出たときに数え、以後は使い回す（全ブロック分を先に数えない）。
    #複数のスレッドが同時に数えても同じ内容になる
    def offsets
      @offsets ||= begin
        list = Array.new(@size)
        position = 0
        @size.times do |index|
          list[index] = position
          position = @packed.index(SEPARATOR, position) + 1
        end
        list
      end
    end
  end
end
