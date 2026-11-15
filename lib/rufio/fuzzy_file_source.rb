# frozen_string_literal: true

require_relative 'native_content_search'
require_relative 'fuzzy_candidate_block'

module Rufio
  # Produces display labels and original paths separately. A source belongs to
  # its producer thread, including creation and destruction of the native scan.
  # Batches are FuzzyCandidateBlock: packed labels, with { text:, path: } rows built on demand.
  class FuzzyFileSource
    BATCH_SIZE = 256
    # Zig の走査は 1 回の取り出しで多くのファイルを返すので、大きめのブロックにまとめて登録回数を減らす
    BLOCK_SIZE = 4096

    def initialize(root, native: true)
      @root = File.expand_path(root).freeze
      @prefix = @root.end_with?(File::SEPARATOR) ? @root : @root + File::SEPARATOR
      @native = native
    end

    def each_batch(cancelled:, on_error:)
      return if cancelled.call
      raise Errno::ENOTDIR, @root unless File.directory?(@root)

      if @native && ENV['RUFIO_NATIVE_SEARCH'] != '0' && NativeContentSearch.labels_available?
        scan_labels(cancelled, on_error) { |batch| yield batch }
      elsif @native && ENV['RUFIO_NATIVE_SEARCH'] != '0' && NativeContentSearch.files_available?
        scan_native(cancelled, on_error) { |batch| yield batch }
      else
        scan_ruby(cancelled, on_error) { |batch| yield batch }
      end
    end

    private

    # 1 ブロック分の候補を詰める。Hash や凍結した文字列を候補ごとに作らず、表示名だけを連結する。
    # パスは「ルート/表示名」から組み立て直せるので、scrub した・エンコーディングが違う候補だけ別に持つ。
    class Batch
      def initialize(prefix, on_error)
        @prefix = prefix
        @binary_prefix = prefix.b.freeze
        @on_error = on_error
        reset
      end

      def size
        @builder.size
      end

      def add(path)
        relative = path.delete_prefix(@prefix)
        text = relative.encoding == Encoding::UTF_8 ? relative : relative.dup.force_encoding(Encoding::UTF_8)
        scrubbed = !text.valid_encoding?
        text = text.scrub if scrubbed
        if text.bytesize > FuzzyCandidateBlock::MAX_TEXT_BYTES || text.include?("\0")
          @on_error.call("#{text[0, 200]}: file name cannot be searched")
          return
        end

        @encoding ||= path.encoding
        index = @builder.add(text)
        return unless scrubbed || path.encoding != @encoding || relative.bytesize == path.bytesize

        (@exceptions ||= {})[index] = path.frozen? ? path : path.dup.freeze
      end

      # 詰めた候補をブロックにして取り出す。空なら nil
      def take
        return if @builder.empty?

        block = @builder.build(FuzzyCandidateBlock::PathRows.new(@binary_prefix, @encoding, @exceptions&.freeze))
        reset
        block
      end

      private

      def reset
        @builder = FuzzyCandidateBlock::Builder.new
        @exceptions = nil
        @encoding = nil
      end
    end

    # Zig が相対パスのラベル列を返す場合は、Ruby でファイルごとの文字列を作らずにそのままブロックにする
    def scan_labels(cancelled, on_error)
      scanner = NativeContentSearch.new(roots: [@root], labels: true)
      rows = FuzzyCandidateBlock::PathRows.new(@prefix.b.freeze, Encoding.find('filesystem'))
      batch = Batch.new(@prefix, on_error)
      packed = +''.b
      count = 0
      limit = BATCH_SIZE
      emit = lambda do
        next if count.zero?

        yield FuzzyCandidateBlock.new(packed.freeze, count, rows: rows, checked: true)
        packed = +''.b
        count = 0
        limit = [limit * 2, BLOCK_SIZE].min
      end
      scanner.each_batch(cancelled: cancelled) do |events|
        events.each do |kind, _root_index, value, size|
          break if cancelled.call

          case kind
          when :labels
            packed << value
            count += size
            emit.call if count >= limit
          when :file then batch.add(value) # UTF-8 でない名前
          when :error then on_error.call(value)
          end
        end
        break if cancelled.call

        emit.call
        block = batch.take
        yield block if block
      end
    ensure
      scanner&.close
    end

    def scan_native(cancelled, on_error)
      scanner = NativeContentSearch.new(roots: [@root])
      batch = Batch.new(@prefix, on_error)
      # 最初の結果を早く出すため小さいブロックから始め、倍々に大きくする
      limit = BATCH_SIZE
      scanner.each_batch(cancelled: cancelled, max_events: BLOCK_SIZE) do |events|
        events.each do |kind, _root_index, path|
          break if cancelled.call

          if kind == :file
            batch.add(path)
            if batch.size >= limit
              yield batch.take
              limit = [limit * 2, BLOCK_SIZE].min
            end
          elsif kind == :error
            on_error.call(path)
          end
        end
        block = batch.take
        yield block if block && !cancelled.call
      end
    ensure
      scanner&.close
    end

    def scan_ruby(cancelled, on_error)
      pending = [@root]
      batch = Batch.new(@prefix, on_error)
      until pending.empty? || cancelled.call
        directory = pending.pop
        begin
          Dir.each_child(directory) do |name|
            break if cancelled.call

            path = File.join(directory, name)
            begin
              stat = File.lstat(path)
              if stat.directory?
                pending << path
              elsif stat.file? || (stat.symlink? && File.file?(path))
                batch.add(path)
                yield batch.take if batch.size >= BATCH_SIZE
              end
            rescue SystemCallError, IOError => e
              on_error.call("#{path}: #{e.message}")
            end
          end
        rescue SystemCallError, IOError => e
          on_error.call("#{directory}: #{e.message}")
        end
      end
      block = batch.take
      yield block if block && !cancelled.call
    end
  end
end
