# frozen_string_literal: true

require 'fiddle'
require_relative 'native_scanner'
require_relative 'native_scanner_zig'

module Rufio
  # Zig 実装のコンテンツ検索（G mode 用）。
  # Ruby 実装（GlobalSearch#scan_content）と同じ結果を、並列走査と SIMD 検索で返す。
  class NativeContentSearch
    HEADER_SIZE = 25
    HEADER_FORMAT = 'CL<Q<L<L<L<'
    STATE_SCANNING = 1
    KINDS = { 1 => :match, 2 => :document, 3 => :error }.freeze
    MAX_QUERY_BYTES = 1024
    POLL_INTERVAL = 0.001

    # 検索をまたいでファイル内容を保持するキャッシュ（mtime/inode/サイズで毎回検証する）
    class Cache
      DEFAULT_MAX_BYTES = 256 * 1024 * 1024

      attr_reader :handle

      def self.finalizer(handle)
        proc { NativeScannerZigFFI.core_cache_destroy(handle) }
      end

      def initialize(max_bytes: DEFAULT_MAX_BYTES)
        @handle = NativeScannerZigFFI.core_cache_create(max_bytes)
        raise StandardError, 'Failed to create search cache' if @handle.zero?

        ObjectSpace.define_finalizer(self, self.class.finalizer(@handle))
      end

      def cached_bytes
        @handle.zero? ? 0 : NativeScannerZigFFI.core_cache_bytes(@handle)
      end

      # このキャッシュを使う検索をすべて close してから呼ぶこと
      def close
        return if @handle.zero?

        ObjectSpace.undefine_finalizer(self)
        NativeScannerZigFFI.core_cache_destroy(@handle)
        @handle = 0
      end
    end

    def self.available?
      NativeScannerZigFFI.search_available?
    end

    # Zig 側は ASCII のみ大文字小文字を畳み込むため、大文字小文字を持つ非 ASCII 文字は Ruby 実装に任せる
    def self.supports_query?(query)
      return false if query.empty? || query.bytesize > MAX_QUERY_BYTES

      query.each_char.all? { |char| char.ascii_only? || (char.upcase == char && char.downcase == char) }
    end

    # マッチ周辺のバイト列から Ruby 実装と同じスニペット（30 文字前から 200 文字）を作る
    def self.snippet(window, offset)
      line = window.dup.force_encoding(Encoding::UTF_8).scrub
      match_index = window.byteslice(0, offset).force_encoding(Encoding::UTF_8).scrub.length
      line[[match_index - 30, 0].max, 200].to_s.strip
    end

    def initialize(roots:, query:, excluded_extensions: [], document_extensions: [], cache: nil, threads: 0)
      raise StandardError, 'Zig content search is not available' unless self.class.available?

      @cache = cache
      @path_encoding = Encoding.find('filesystem')
      roots_buf = pack(roots)
      query_buf = query.b
      excluded_buf = pack(excluded_extensions)
      documents_buf = pack(document_extensions)
      @handle = NativeScannerZigFFI.core_search_create(
        roots_buf, roots_buf.bytesize, query_buf, query_buf.bytesize,
        excluded_buf, excluded_buf.bytesize, documents_buf, documents_buf.bytesize,
        threads, cache ? cache.handle : 0
      )
      raise StandardError, 'Failed to start native search' if @handle.zero?

      @length = Fiddle::Pointer.malloc(8, Fiddle::RUBY_FREE)
      @skipped = 0
    end

    # [:match, root_index, path, line_number, snippet] / [:document, root_index, path] /
    # [:error, root_index, message] / [:skipped, count] を検索終了まで順に返す
    def each_event(&block)
      return enum_for(:each_event) unless block_given?

      each_batch { |batch| batch.each(&block) }
    end

    # 1 回の取り出しごとにイベント配列を返す（UI へまとめて渡すため）
    def each_batch
      return enum_for(:each_batch) unless block_given?

      loop do
        state = NativeScannerZigFFI.core_search_state(@handle)
        data = drain
        batch = []
        each_record(data) { |event| batch << event }
        skipped = NativeScannerZigFFI.core_search_skipped(@handle)
        if skipped > @skipped
          batch << [:skipped, skipped - @skipped]
          @skipped = skipped
        end
        yield batch unless batch.empty?
        break if data.empty? && state != STATE_SCANNING

        sleep POLL_INTERVAL if data.empty?
      end
    end

    def close
      return if @handle.nil? || @handle.zero?

      NativeScannerZigFFI.core_search_destroy(@handle)
      @handle = 0
    end

    private

    def pack(values)
      values.map { |value| value.to_s.b }.join("\0")
    end

    def drain
      pointer = NativeScannerZigFFI.core_search_drain(@handle, @length)
      length = @length[0, 8].unpack1('Q')
      length.zero? ? ''.b : pointer.to_str(length)
    end

    def each_record(data)
      position = 0
      while position + HEADER_SIZE <= data.bytesize
        kind, root, line, offset, path_length, extra_length = data.byteslice(position, HEADER_SIZE).unpack(HEADER_FORMAT)
        position += HEADER_SIZE
        path = data.byteslice(position, path_length).force_encoding(@path_encoding)
        position += path_length
        extra = data.byteslice(position, extra_length)
        position += extra_length

        case KINDS[kind]
        when :match then yield [:match, root, path, line, self.class.snippet(extra, offset)]
        when :document then yield [:document, root, path]
        when :error then yield [:error, root, "#{path}: #{extra.force_encoding(Encoding::UTF_8).scrub}"]
        end
      end
    end
  end
end
