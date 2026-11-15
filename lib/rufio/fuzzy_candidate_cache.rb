# frozen_string_literal: true

require 'thread'
require_relative 'fuzzy_file_source'
require_relative 'fuzzy_candidate_block'

module Rufio
  # s / / を同じディレクトリで開き直したとき、走査済みの候補一覧を再利用する。
  # 容量（合計候補数・ディレクトリ数）と有効期限で制限し、最近使ったものから残す。
  # 検索インデックスは各セッションのワーカー専有のまま、候補だけを流し直して作り直す。
  # 候補は FuzzyCandidateBlock（表示名を NUL で終端して連結したバイト列）で保持する（1 件 1 Hash より大幅に小さい）。
  # パスが「ルート/表示名」と同じバイト列なら持たず、行を作るときに組み立て直す。
  # 走査がブロックを出した場合はそれをそのまま保存し、再表示するセッションにも同じブロックを渡す（コピーしない）。
  class FuzzyCandidateCache
    # 既定値。利用者は config.rb の FUZZY_SEARCH_CACHE で変更できる（ConfigLoader.fuzzy_search_cache）
    DEFAULT_MAX_ENTRIES = 200_000
    DEFAULT_MAX_ROOTS = 4
    DEFAULT_TTL = 300
    BLOCK_SIZE = 4096
    SEPARATOR = "\0"
    EMPTY = [].freeze

    # 保存済みの一覧。候補は FuzzyCandidateBlock のまま持ち、再表示するセッションと共有する
    class Entry
      attr_reader :blocks, :errors, :stored_at, :size

      def initialize(blocks:, errors:, stored_at:)
        @blocks = blocks.freeze
        @size = blocks.sum(&:size)
        @errors = errors
        @stored_at = stored_at
        freeze
      end

      # 全件を行に展開する（展開結果は保持しない）。再表示では使わない
      def rows
        @blocks.flat_map(&:to_a).freeze
      end
    end

    # 候補を詰める。上限を超えたら以降は捨てて nil を返す
    class Packer
      def initialize(root, max_entries)
        @prefix = (root.end_with?(File::SEPARATOR) ? root : root + File::SEPARATOR).b.freeze
        @max_entries = max_entries
        @blocks = []
        @size = 0
        reset
      end

      def overflow?
        @blocks.nil?
      end

      # text と path を持つ行を 1 件詰める
      def add(row)
        return false if overflow?

        text = row.is_a?(Hash) ? row[:text] : nil
        path = row.is_a?(Hash) ? row[:path] : nil
        return overflow! unless text.is_a?(String) && path.is_a?(String) && @size < @max_entries

        text = text.dup.force_encoding(Encoding::UTF_8)
        text = text.scrub unless text.valid_encoding?
        bytes = path.b
        if text.include?(SEPARATOR) || bytes.include?(SEPARATOR) || text.bytesize > FuzzyCandidateBlock::MAX_TEXT_BYTES
          return overflow!
        end

        @encoding ||= path.encoding
        index = @builder.add(text)
        unless path.encoding == @encoding && bytes == @prefix + text.b
          (@exceptions ||= {})[index] = path.frozen? ? path : path.dup.freeze
        end
        @size += 1
        flush if @builder.size >= BLOCK_SIZE
        true
      end

      # 走査が出したブロックは作り直さず、そのまま保存する
      def add_block(block)
        return false if overflow?
        return overflow! if @size + block.size > @max_entries

        flush
        @blocks << block
        @size += block.size
        true
      end

      def add_batch(batch)
        return add_block(batch) if batch.is_a?(FuzzyCandidateBlock)

        batch.each { |row| break unless add(row) }
        !overflow?
      end

      def entry(errors, stored_at)
        return nil if overflow?

        flush
        Entry.new(blocks: @blocks, errors: errors.map { |message| message.to_s.dup.freeze }.freeze, stored_at: stored_at)
      end

      private

      def overflow!
        @blocks = nil
        @builder = nil
        false
      end

      def flush
        return if @builder.empty?

        @blocks << @builder.build(FuzzyCandidateBlock::PathRows.new(@prefix, @encoding, @exceptions&.freeze))
        reset
      end

      def reset
        @builder = FuzzyCandidateBlock::Builder.new
        @exceptions = nil
        @encoding = nil
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

    # 保存済みのブロックを順に流し、走査時のエラーも再現する
    class CachedSource
      def initialize(entry)
        @entry = entry
      end

      def each_batch(cancelled:, on_error:)
        @entry.errors.each { |message| on_error.call(message) }
        @entry.blocks.each do |block|
          break if cancelled.call

          yield block
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
          packer.add_batch(batch) unless packer.overflow?
          yield batch
        end
        @cache.store_entry(@root, packer.entry(errors, @cache.now)) unless cancelled.call
      end
    end
  end
end
