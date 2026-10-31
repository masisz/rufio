# frozen_string_literal: true

require 'fileutils'
require 'zlib'
require_relative 'zip_archive'
require_relative 'native_zip'

module Rufio
  # ZIPアーカイブの安全な展開（Pure Ruby 実装。ネイティブ実装の互換基準でもある）
  #
  # 書き込み前に全エントリを検証し、1件でも危険なエントリがあれば何も書かずに中止する。
  # - Zip Slip: 絶対パス・ドライブレター・".." を含むエントリ、展開先外を指すエントリを拒否
  # - シンボリックリンクのエントリは展開しない（展開先の既存シンボリックリンクも辿らない）
  # - ZIP 爆弾: 展開後合計サイズ・エントリ数・圧縮率の上限、データ範囲が重なるエントリの拒否、
  #   宣言サイズを超えて伸長されたら中止
  # - CRC-32 不一致のファイルは残さない（一時ファイルに書いてから rename）
  # - 既存ファイルは overwrite: true のときだけ上書きする
  class ZipExtractor
    class Error < StandardError; end
    class UnsafeEntryError < Error; end
    class LimitExceededError < Error; end
    class ConflictError < Error; end
    class CorruptEntryError < Error; end
    class CancelledError < Error; end

    DEFAULT_MAX_TOTAL_SIZE = 16 * 1024 * 1024 * 1024 # 16 GiB
    DEFAULT_MAX_ENTRIES = 100_000
    DEFAULT_MAX_RATIO = 1000
    # 圧縮率の上限はこのサイズを超えるエントリにだけ適用する（小さな高圧縮ファイルは正常）
    RATIO_CHECK_MIN_SIZE = 1024 * 1024

    LOCAL_HEADER_SIGNATURE = 0x04034b50
    LOCAL_HEADER_SIZE = 30
    CHUNK_SIZE = 64 * 1024
    SUPPORTED_METHODS = [0, 8].freeze

    Result = Struct.new(:extracted, :skipped, :bytes_written, keyword_init: true)

    # @param zip_path [String]
    # @param destination [String] 展開先ディレクトリ（なければ作成する）
    # @param progress [#call, nil] (書き込み済みバイト数, 合計バイト数) を受け取る
    # @param cancelled [#call, nil] true を返したら CancelledError で中止する
    # @param native [Boolean] Zig 実装でデータを並列に伸長する（検証は常に Ruby 側で行う）
    def initialize(zip_path, destination, overwrite: false,
                   max_total_size: DEFAULT_MAX_TOTAL_SIZE, max_entries: DEFAULT_MAX_ENTRIES,
                   max_ratio: DEFAULT_MAX_RATIO, progress: nil, cancelled: nil, native: NativeZip.available?)
      @zip_path = zip_path
      @destination = File.expand_path(destination)
      @overwrite = overwrite
      @max_total_size = max_total_size
      @max_entries = max_entries
      @max_ratio = max_ratio
      @progress = progress
      @cancelled = cancelled
      @native = native
    end

    def extract
      listing = ZipArchive.list(@zip_path)
      raise LimitExceededError, "Too many entries (#{listing.total_entries} > #{@max_entries})" if listing.total_entries > @max_entries

      File.open(@zip_path, 'rb') do |io|
        plan, skipped = build_plan(io, listing)
        FileUtils.mkdir_p(@destination)
        root = File.realpath(@destination)
        total = plan.sum { |item| item[:entry].size }

        # 書き込み先をすべて確定させてからデータを書く
        plan.each do |item|
          check_cancel!
          item[:target] = safe_target(root, item[:relative])
          make_directory(root, item[:entry].directory? ? item[:target] : File.dirname(item[:target]))
        end

        files = plan.reject { |item| item[:entry].directory? }
        written = if @native && !files.empty?
                    write_files_native(files, total)
                  else
                    files.reduce(0) do |sum, item|
                      check_cancel!
                      write_file(io, item, sum, total)
                    end
                  end
        apply_directory_times(root, plan)

        Result.new(extracted: plan.map { |item| item[:relative] }, skipped: skipped, bytes_written: written)
      end
    end

    # 展開先からの相対パスに正規化する。危険な名前は UnsafeEntryError
    def self.normalize_entry_name(name)
      raise UnsafeEntryError, 'Entry name is empty' if name.nil? || name.empty?
      raise UnsafeEntryError, "Entry name contains NUL: #{name.inspect}" if name.include?("\0")

      path = name.tr('\\', '/')
      raise UnsafeEntryError, "Absolute path entry: #{name}" if path.start_with?('/') || path.match?(%r{\A[A-Za-z]:})

      parts = path.split('/').reject { |part| part.empty? || part == '.' }
      raise UnsafeEntryError, "Parent directory reference: #{name}" if parts.include?('..')
      raise UnsafeEntryError, "Entry name is empty: #{name}" if parts.empty?
      # Windows では ':' が代替データストリームやドライブ指定になる
      raise UnsafeEntryError, "Entry name contains ':': #{name}" if Gem.win_platform? && parts.any? { |part| part.include?(':') }

      parts.join('/')
    end

    private

    # 書き込み前に全エントリを検証する
    def build_plan(io, listing)
      file_size = io.size
      seen = {}
      skipped = []
      plan = []
      total = 0

      ranges = listing.entries.map do |entry|
        start = data_start(io, entry, file_size)
        finish = start + entry.compressed_size
        raise CorruptEntryError, "Entry data is out of range: #{entry.name}" if finish > listing.central_directory_offset

        [entry.local_header_offset, finish, entry, start]
      end
      check_overlaps(ranges)

      ranges.each do |_header, _finish, entry, start|
        relative = self.class.normalize_entry_name(entry.name)
        if (reason = skip_reason(entry))
          skipped << { name: entry.name, reason: reason }
          next
        end

        raise UnsafeEntryError, "Duplicate entry: #{entry.name}" if seen[relative] && !entry.directory?

        seen[relative] = true
        check_limits(entry)
        total += entry.size
        raise LimitExceededError, "Total size exceeds limit (#{@max_total_size} bytes)" if total > @max_total_size

        check_conflict(relative, entry)
        plan << { entry: entry, relative: relative, data_offset: start }
      end

      [plan, skipped]
    end

    def skip_reason(entry)
      return 'symlink' if entry.symlink?
      return 'encrypted' if entry.encrypted?
      return "unsupported method (#{ZipArchive.method_name(entry.method)})" unless entry.directory? || SUPPORTED_METHODS.include?(entry.method)

      nil
    end

    def data_start(io, entry, file_size)
      offset = entry.local_header_offset
      raise CorruptEntryError, "Local header is out of range: #{entry.name}" if offset + LOCAL_HEADER_SIZE > file_size

      io.seek(offset)
      sig, *, name_length, extra_length = io.read(LOCAL_HEADER_SIZE).unpack('VvvvvvVVVvv')
      raise CorruptEntryError, "Invalid local header: #{entry.name}" unless sig == LOCAL_HEADER_SIGNATURE

      offset + LOCAL_HEADER_SIZE + name_length + extra_length
    end

    # 同じデータ範囲を複数エントリで共有する ZIP 爆弾（重複参照型）を拒否する
    def check_overlaps(ranges)
      ranges.sort_by(&:first).each_cons(2) do |(_, prev_finish, prev, _), (next_start, _, entry, _)|
        raise UnsafeEntryError, "Overlapping entries: #{prev.name}, #{entry.name}" if next_start < prev_finish
      end
    end

    def check_limits(entry)
      return if entry.directory?
      return if entry.size <= RATIO_CHECK_MIN_SIZE

      if entry.compressed_size.zero? || entry.size / entry.compressed_size > @max_ratio
        raise LimitExceededError, "Compression ratio exceeds limit (#{@max_ratio}:1): #{entry.name}"
      end
    end

    def check_conflict(relative, entry)
      target = File.join(@destination, relative)
      return unless File.exist?(target) || File.symlink?(target)
      return if entry.directory? && File.directory?(target) && !File.symlink?(target)
      return if @overwrite && File.file?(target) && !File.symlink?(target)

      raise ConflictError, "Already exists: #{relative}"
    end

    # 展開先の既存シンボリックリンクを辿って外に出ないことを確認する
    def safe_target(root, relative)
      target = File.join(root, relative)
      current = root
      relative.split('/')[0...-1].each do |part|
        current = File.join(current, part)
        next if verified_dirs.include?(current)
        raise UnsafeEntryError, "Path goes through a symlink: #{relative}" if File.symlink?(current)
      end
      raise UnsafeEntryError, "Target is a symlink: #{relative}" if File.symlink?(target)

      target
    end

    # 作成・検証済みのディレクトリ（同じディレクトリへの多数のファイルで検証を繰り返さない）
    def verified_dirs
      @verified_dirs ||= {}
    end

    def make_directory(root, path)
      return if verified_dirs.include?(path)

      FileUtils.mkdir_p(path)
      real = File.realpath(path)
      raise UnsafeEntryError, "Directory escapes destination: #{path}" unless real == root || real.start_with?(root.end_with?('/') ? root : "#{root}/")

      # safe_target で途中にシンボリックリンクがないことを確認済みなので、祖先も検証済みとして扱う
      current = path
      until current == root || current.length <= root.length || verified_dirs.include?(current)
        verified_dirs[current] = true
        current = File.dirname(current)
      end
    end

    def write_file(io, item, written, total)
      entry = item[:entry]
      temp = temp_path(item[:target])
      crc = 0
      size = 0

      File.open(temp, File::WRONLY | File::CREAT | File::EXCL | File::BINARY, 0o600) do |out|
        each_chunk(io, item) do |chunk|
          size += chunk.bytesize
          raise CorruptEntryError, "Entry is larger than declared: #{entry.name}" if size > entry.size

          crc = Zlib.crc32(chunk, crc)
          out.write(chunk)
          written += chunk.bytesize
          @progress&.call(written, total)
          check_cancel!
        end
      end

      raise CorruptEntryError, "Entry is smaller than declared: #{entry.name}" if size != entry.size
      raise CorruptEntryError, "CRC-32 mismatch: #{entry.name}" if crc != entry.crc32

      finish_file(temp, item)
      written
    ensure
      File.unlink(temp) if temp && File.exist?(temp)
    end

    # Zig 実装で全ファイルを並列に一時ファイルへ伸長し、すべて検証が通ってから rename する
    def write_files_native(files, total)
      temps = files.map { |item| temp_path(item[:target]) }
      tasks = files.each_with_index.map do |item, index|
        entry = item[:entry]
        { data_offset: item[:data_offset], compressed_size: entry.compressed_size, size: entry.size,
          crc32: entry.crc32, method: entry.method, output: temps[index] }
      end

      job = NativeZip.extract(@zip_path, tasks)
      begin
        state = job.wait(progress: @progress && ->(done, _) { @progress.call(done, total) }, cancelled: @cancelled)
        raise CancelledError, 'Extraction cancelled' if state == NativeZip::STATE_CANCELLED

        files.each_with_index { |item, index| check_native_status(job.status(index), item[:entry]) }
        files.each_with_index { |item, index| finish_file(temps[index], item) }
      ensure
        job.close
        temps.each { |temp| File.unlink(temp) if File.exist?(temp) }
      end
      total
    end

    def check_native_status(status, entry)
      case status
      when NativeZip::STATUS_OK then nil
      when NativeZip::STATUS_CRC_MISMATCH then raise CorruptEntryError, "CRC-32 mismatch: #{entry.name}"
      when NativeZip::STATUS_TOO_LARGE then raise CorruptEntryError, "Entry is larger than declared: #{entry.name}"
      when NativeZip::STATUS_SIZE_MISMATCH then raise CorruptEntryError, "Entry is smaller than declared: #{entry.name}"
      when NativeZip::STATUS_CORRUPT then raise CorruptEntryError, "Invalid compressed data: #{entry.name}"
      when NativeZip::STATUS_CANCELLED then raise CancelledError, 'Extraction cancelled'
      else raise Error, "Failed to write #{entry.name}"
      end
    end

    def temp_path(target)
      "#{target}.rufio-#{Process.pid}-#{rand(1 << 32).to_s(16)}.tmp"
    end

    def finish_file(temp, item)
      entry = item[:entry]
      apply_mode(temp, entry)
      File.rename(temp, item[:target])
      File.utime(entry.mtime, entry.mtime, item[:target]) if entry.mtime
    end

    def each_chunk(io, item)
      entry = item[:entry]
      io.seek(item[:data_offset])
      remaining = entry.compressed_size
      inflater = entry.method == 8 ? Zlib::Inflate.new(-Zlib::MAX_WBITS) : nil

      while remaining.positive?
        data = io.read([remaining, CHUNK_SIZE].min)
        raise CorruptEntryError, "Unexpected end of data: #{entry.name}" if data.nil? || data.empty?

        remaining -= data.bytesize
        if inflater
          # 伸長結果が宣言サイズを大きく超えないよう、小分けに伸長する
          inflater.inflate(data) { |chunk| yield chunk }
        else
          yield data
        end
      end
      inflater&.finish&.then { |rest| yield rest unless rest.empty? }
    rescue Zlib::Error => e
      raise CorruptEntryError, "Invalid compressed data: #{entry.name} (#{e.message})"
    ensure
      inflater&.close
    end

    # 実行権限だけを引き継ぐ（setuid / setgid / sticky や他者書き込み権限は付けない）
    def apply_mode(path, entry)
      return if Gem.win_platform?

      @umask ||= File.umask
      mode = entry.unix_mode
      File.chmod(mode && (mode & 0o111).nonzero? ? 0o777 & ~@umask & ~0o022 : 0o666 & ~@umask, path)
    end

    def apply_directory_times(root, plan)
      plan.reverse_each do |item|
        entry = item[:entry]
        next unless entry.directory? && entry.mtime

        File.utime(entry.mtime, entry.mtime, File.join(root, item[:relative]))
      end
    end

    def check_cancel!
      raise CancelledError, 'Extraction cancelled' if @cancelled&.call
    end
  end
end
