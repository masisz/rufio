# frozen_string_literal: true

require 'thread'
require_relative 'fuzzy_file_source'

module Rufio
  # s / / を同じディレクトリで開き直したとき、走査済みの候補一覧を再利用する。
  # 容量（合計候補数・ディレクトリ数）と有効期限で制限し、最近使ったものから残す。
  # 検索インデックスは各セッションのワーカー専有のまま、候補だけを流し直して作り直す。
  # 候補は「表示名 NUL パス NUL」を連結した 1 本のバイト列で保持する（1 件 1 Hash より大幅に小さい）。
  # パスが「ルート/表示名」と同じバイト列なら省略し、再生時に組み立て直す。保持するのは text と path だけ。
  class FuzzyCandidateCache
    # 既定値。利用者は config.rb の FUZZY_SEARCH_CACHE で変更できる（ConfigLoader.fuzzy_search_cache）
    DEFAULT_MAX_ENTRIES = 200_000
    DEFAULT_MAX_ROOTS = 4
    DEFAULT_TTL = 300
    BATCH_SIZE = 256
    SEPARATOR = "\0"
    EMPTY = [].freeze

    # 保存済みの一覧。rows は呼ぶたびに展開する（展開結果は保持しない）
    class Entry
      attr_reader :errors, :stored_at, :size

      def initialize(prefix:, packed:, size:, encoding:, errors:, stored_at:)
        @prefix = prefix
        @packed = packed
        @size = size
        @encoding = encoding
        @errors = errors
        @stored_at = stored_at
        freeze
      end

      def rows
        list = []
        each_slice(BATCH_SIZE) { |batch| list.concat(batch) }
        list.freeze
      end

      # 先頭から size 件ずつ展開して渡す。全件を一度に展開しないので最初の候補がすぐ届く
      def each_slice(size)
        position = 0
        batch = []
        @size.times do
          text_end = @packed.index(SEPARATOR, position)
          path_end = @packed.index(SEPARATOR, text_end + 1) || @packed.bytesize
          text = @packed.byteslice(position, text_end - position).force_encoding(Encoding::UTF_8)
          path = path_end == text_end + 1 ? @prefix + text.b : @packed.byteslice(text_end + 1, path_end - text_end - 1)
          batch << { text: text.freeze, path: path.force_encoding(@encoding).freeze }.freeze
          position = path_end + 1
          next if batch.length < size

          yield batch.freeze
          batch = []
        end
        yield batch.freeze unless batch.empty?
      end
    end

    # 候補を 1 件ずつ詰める。上限を超えたら以降は捨てて nil を返す
    class Packer
      def initialize(root, max_entries)
        @prefix = (root.end_with?(File::SEPARATOR) ? root : root + File::SEPARATOR).b.freeze
        @max_entries = max_entries
        @buffer = +''.b
        @size = 0
        @encoding = Encoding::UTF_8
      end

      def overflow?
        @buffer.nil?
      end

      def add(row)
        return false if overflow?

        text = row.is_a?(Hash) ? row[:text] : nil
        path = row.is_a?(Hash) ? row[:path] : nil
        unless text.is_a?(String) && path.is_a?(String) && @size < @max_entries
          @buffer = nil
          return false
        end

        text = text.dup.force_encoding(Encoding::UTF_8)
        text = text.scrub unless text.valid_encoding?
        bytes = path.b
        if text.include?(SEPARATOR) || bytes.include?(SEPARATOR)
          @buffer = nil
          return false
        end

        @encoding = path.encoding
        @buffer << text.b << SEPARATOR
        @buffer << bytes unless bytes == @prefix + text.b
        @buffer << SEPARATOR
        @size += 1
        true
      end

      def entry(errors, stored_at)
        return nil if overflow?

        packed = @size.zero? ? @buffer : @buffer.byteslice(0, @buffer.bytesize - 1)
        Entry.new(prefix: @prefix, packed: packed.freeze, size: @size, encoding: @encoding,
                  errors: errors.map { |message| message.to_s.dup.freeze }.freeze, stored_at: stored_at)
      end
    end

    def initialize(max_entries: DEFAULT_MAX_ENTRIES, max_roots: DEFAULT_MAX_ROOTS, ttl: DEFAULT_TTL, clock: nil)
      @max_entries = max_entries
      @max_roots = max_roots
      @ttl = ttl
      @clock = clock || -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
      @mutex = Mutex.new
      @entries = {} # 挿入順 = 使用順（先頭が最も古い）
    end

    def fetch(root)
      key = normalize(root)
      @mutex.synchronize do
        entry = @entries.delete(key)
        return nil unless entry
        return nil if expired?(entry)

        @entries[key] = entry
      end
    end

    # rows は :text と :path を持つ候補。上限を超える一覧は保存しない
    def store(root, rows, errors: [])
      return false if rows.length > @max_entries

      key = normalize(root)
      packer = Packer.new(key, @max_entries)
      rows.each { |row| break unless packer.add(row) }
      store_entry(key, packer.entry(errors, @clock.call))
    end

    # RecordingSource が詰め終えた一覧を保存する
    def store_entry(root, entry)
      return false unless entry

      key = normalize(root)
      @mutex.synchronize do
        @entries.delete(key)
        @entries[key] = entry
        @entries.shift while @entries.length > @max_roots || total_entries > @max_entries
      end
      true
    end

    def delete(root)
      key = normalize(root)
      @mutex.synchronize { @entries.delete(key) }
      nil
    end

    def clear
      @mutex.synchronize { @entries.clear }
      nil
    end

    def size
      @mutex.synchronize do
        @entries.delete_if { |_, entry| expired?(entry) }
        @entries.length
      end
    end

    # 保存時刻と有効期限の判定に使う時刻（monotonic）
    def now
      @clock.call
    end

    def entry_count
      @mutex.synchronize { total_entries }
    end

    # キャッシュがあれば [再生用ソース, 保存時刻]、なければ [記録付きの走査ソース, nil] を返す。
    # ブロックで走査ソースを差し替えられる（既定は FuzzyFileSource）。
    def source_for(root, native: true)
      entry = fetch(root)
      return [CachedSource.new(entry), entry.stored_at] if entry

      scan = block_given? ? yield : FuzzyFileSource.new(root, native: native)
      [RecordingSource.new(scan, self, root, @max_entries), nil]
    end

    private

    def normalize(root)
      File.expand_path(root.to_s)
    end

    def expired?(entry)
      @clock.call - entry.stored_at > @ttl
    end

    def total_entries
      @entries.each_value.sum(&:size)
    end

    # 保存済みの候補をバッチに分けて流し、走査時のエラーも再現する
    class CachedSource
      def initialize(entry)
        @entry = entry
      end

      def each_batch(cancelled:, on_error:)
        @entry.errors.each { |message| on_error.call(message) }
        @entry.each_slice(BATCH_SIZE) do |batch|
          break if cancelled.call

          yield batch
        end
      end
    end

    # 走査結果をそのまま流しつつ記録し、最後まで走査できたときだけ保存する
    class RecordingSource
      def initialize(scan, cache, root, max_entries)
        @scan = scan
        @cache = cache
        @root = root
        @max_entries = max_entries
      end

      def each_batch(cancelled:, on_error:)
        packer = Packer.new(File.expand_path(@root.to_s), @max_entries)
        errors = []
        recording = ->(message) { errors << message; on_error.call(message) }
        @scan.each_batch(cancelled: cancelled, on_error: recording) do |batch|
          batch.each { |row| break unless packer.add(row) } unless packer.overflow?
          yield batch
        end
        @cache.store_entry(@root, packer.entry(errors, @cache.now)) unless cancelled.call
      end
    end
  end
end
