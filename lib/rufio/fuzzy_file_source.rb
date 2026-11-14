# frozen_string_literal: true

require_relative 'native_content_search'

module Rufio
  # Produces display labels and original paths separately. A source belongs to
  # its producer thread, including creation and destruction of the native scan.
  class FuzzyFileSource
    BATCH_SIZE = 256

    def initialize(root, native: true)
      @root = File.expand_path(root).freeze
      @prefix = @root.end_with?(File::SEPARATOR) ? @root : @root + File::SEPARATOR
      @native = native
    end

    def each_batch(cancelled:, on_error:)
      return if cancelled.call
      raise Errno::ENOTDIR, @root unless File.directory?(@root)

      if @native && ENV['RUFIO_NATIVE_SEARCH'] != '0' && NativeContentSearch.files_available?
        scan_native(cancelled, on_error) { |batch| yield batch }
      else
        scan_ruby(cancelled, on_error) { |batch| yield batch }
      end
    end

    private

    def entry(path)
      relative = path.delete_prefix(@prefix)
      { text: relative.dup.force_encoding(Encoding::UTF_8).scrub, path: path }
    end

    def scan_native(cancelled, on_error)
      scanner = NativeContentSearch.new(roots: [@root])
      scanner.each_batch(cancelled: cancelled) do |events|
        batch = []
        events.each do |kind, _root_index, path|
          break if cancelled.call

          if kind == :file
            batch << entry(path)
            if batch.length >= BATCH_SIZE
              yield batch
              batch = []
            end
          elsif kind == :error
            on_error.call(path)
          end
        end
        yield batch unless batch.empty? || cancelled.call
      end
    ensure
      scanner&.close
    end

    def scan_ruby(cancelled, on_error)
      pending = [@root]
      batch = []
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
                batch << entry(path)
                if batch.length >= BATCH_SIZE
                  yield batch
                  batch = []
                end
              end
            rescue SystemCallError, IOError => e
              on_error.call("#{path}: #{e.message}")
            end
          end
        rescue SystemCallError, IOError => e
          on_error.call("#{directory}: #{e.message}")
        end
      end
      yield batch unless batch.empty? || cancelled.call
    end
  end
end
