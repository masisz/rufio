# frozen_string_literal: true

require 'fileutils'
require 'zlib'
require_relative 'zip_archive'
require_relative 'native_zip'

module Rufio
  # ZIPアーカイブの作成（Pure Ruby 実装。ネイティブ実装の互換基準でもある）
  #
  # - ファイル名は UTF-8（汎用フラグ bit 11）で格納する
  # - Deflate で縮まないファイルは Stored で格納し直す
  # - 4GiB 超のファイル・オフセット、65535 件超のエントリでは ZIP64 を使う
  # - シンボリックリンクは辿らずにスキップする
  # - 一時ファイルに書いてから rename するので、失敗・中止時に壊れたアーカイブを残さない
  class ZipWriter
    class Error < StandardError; end
    class ConflictError < Error; end
    class CancelledError < Error; end

    LOCAL_HEADER_SIGNATURE = 0x04034b50
    CHUNK_SIZE = 64 * 1024
    MAX32 = 0xFFFFFFFF
    MAX16 = 0xFFFF
    # Deflate で僅かに膨らんでも 32bit に収まるよう、このサイズ以上は最初から ZIP64 拡張を付ける
    ZIP64_LOCAL_THRESHOLD = 0xFFFF0000
    VERSION_DEFAULT = 20
    VERSION_ZIP64 = 45
    VERSION_MADE_BY = (ZipArchive::HOST_UNIX << 8) | 63
    METHOD_STORED = 0
    METHOD_DEFLATE = 8
    # これ未満のファイルは Zig に渡さずその場で圧縮する（一時ファイルの作成・コピーの方が高くつく）
    NATIVE_MIN_SIZE = 1024 * 1024

    Result = Struct.new(:added, :skipped, :bytes_read, keyword_init: true)
    Item = Struct.new(:path, :name, :directory, :size, :mtime, :mode, keyword_init: true)

    # @param zip_path [String] 作成するZIPファイル
    # @param base_dir [String] アーカイブ内パスの基準ディレクトリ
    # @param paths [Array<String>] base_dir からの相対パス（ディレクトリは再帰的に追加）
    # @param native [Boolean] Zig 実装でファイルを並列に圧縮してから順に格納する
    def initialize(zip_path, base_dir, paths, level: Zlib::DEFAULT_COMPRESSION, overwrite: false,
                   progress: nil, cancelled: nil, native: NativeZip.available?)
      @zip_path = File.expand_path(zip_path)
      @base_dir = File.expand_path(base_dir)
      @paths = paths
      @level = level
      @overwrite = overwrite
      @progress = progress
      @cancelled = cancelled
      @native = native
    end

    def write
      raise ConflictError, "Already exists: #{@zip_path}" if File.exist?(@zip_path) && !@overwrite

      items, skipped = collect_items
      total = items.sum(&:size)
      temp = "#{@zip_path}.rufio-#{Process.pid}-#{rand(1 << 32).to_s(16)}.tmp"
      bytes_read = 0
      prepared = {}
      native_items = @native ? items.select { |item| !item.directory && item.size >= NATIVE_MIN_SIZE } : []
      unless native_items.empty?
        parts_dir = "#{temp}.parts"
        Dir.mkdir(parts_dir, 0o700)
        prepared = deflate_natively(native_items, parts_dir, total)
        bytes_read = native_items.sum(&:size)
      end

      File.open(temp, File::RDWR | File::CREAT | File::EXCL | File::BINARY, 0o644) do |out|
        centrals = items.map do |item|
          check_cancel!
          record = write_entry(out, item, prepared[item]) do |count|
            bytes_read += count
            @progress&.call(bytes_read, total)
            check_cancel!
          end
          central_header(item, record)
        end
        write_end_records(out, centrals, items.length)
      end
      File.rename(temp, @zip_path)

      Result.new(added: items.map(&:name), skipped: skipped, bytes_read: bytes_read)
    ensure
      File.unlink(temp) if temp && File.exist?(temp)
      FileUtils.rm_rf(parts_dir) if parts_dir
    end

    private

    def collect_items
      items = []
      skipped = []
      @paths.each do |relative|
        path = File.expand_path(relative, @base_dir)
        raise Error, "Path is outside the base directory: #{relative}" unless path.start_with?(base_prefix)

        collect_path(path, items, skipped)
      end
      [items.uniq(&:name), skipped]
    end

    def base_prefix
      @base_prefix ||= @base_dir.end_with?('/') ? @base_dir : "#{@base_dir}/"
    end

    def collect_path(path, items, skipped)
      name = path.delete_prefix(base_prefix)
      stat = File.lstat(path)

      if stat.symlink?
        skipped << { name: name, reason: 'symlink' }
      elsif File.identical?(path, @zip_path)
        skipped << { name: name, reason: 'output archive' }
      elsif stat.directory?
        items << Item.new(path: path, name: "#{name}/", directory: true, size: 0, mtime: stat.mtime, mode: stat.mode)
        Dir.children(path).sort.each { |child| collect_path(File.join(path, child), items, skipped) }
      elsif stat.file?
        items << Item.new(path: path, name: name, directory: false, size: stat.size, mtime: stat.mtime, mode: stat.mode)
      else
        skipped << { name: name, reason: 'special file' }
      end
    end

    # Zig 実装で各ファイルを raw DEFLATE で parts_dir に並列に圧縮する
    # @return [Hash{Item => Hash}] crc / compressed / part
    def deflate_natively(files, parts_dir, total)
      tasks = files.each_with_index.map { |item, index| { source: item.path, output: File.join(parts_dir, index.to_s) } }
      job = NativeZip.deflate(tasks, level: @level)
      begin
        state = job.wait(progress: @progress && ->(done, _) { @progress.call(done, total) }, cancelled: @cancelled)
        raise CancelledError, 'Archive creation cancelled' if state == NativeZip::STATE_CANCELLED

        files.each_with_index.to_h do |item, index|
          status, crc, compressed, size = job.result(index)
          raise CancelledError, 'Archive creation cancelled' if status == NativeZip::STATUS_CANCELLED
          raise Error, "Failed to compress #{item.name}" unless status == NativeZip::STATUS_OK
          raise Error, "File changed while compressing: #{item.name}" unless size == item.size

          [item, { crc: crc, compressed: compressed, part: tasks[index][:output] }]
        end
      ensure
        job.close
      end
    end

    def write_entry(out, item, prepared = nil)
      offset = out.pos
      name = item.name.encode(Encoding::UTF_8).b
      zip64_local = item.size >= ZIP64_LOCAL_THRESHOLD
      dos_time, dos_date = dos_datetime(item.mtime)
      flags = ZipArchive::FLAG_UTF8

      method = item.directory || item.size.zero? ? METHOD_STORED : METHOD_DEFLATE
      out.write(local_header(name, flags, method, dos_time, dos_date, zip64_local))
      data_offset = out.pos

      crc, compressed = if prepared
                          copy_prepared(out, item, prepared)
                        elsif item.directory
                          [0, 0]
                        else
                          write_data(out, item, method) { |n| yield n }
                        end
      if method == METHOD_DEFLATE && compressed >= item.size
        # 縮まなかったので Stored で書き直す（ヘッダは固定長なので位置は変わらない）
        method = METHOD_STORED
        out.seek(data_offset)
        out.truncate(data_offset)
        crc, compressed = write_data(out, item, method) { |_| nil }
      end
      raise Error, "File too large for this entry: #{item.name}" if !zip64_local && compressed > MAX32

      # 圧縮後のサイズと CRC を入れたローカルヘッダで書き戻す
      finish = out.pos
      out.seek(offset)
      out.write(local_header(name, flags, method, dos_time, dos_date, zip64_local,
                             crc: crc, compressed: compressed, size: item.size))
      out.seek(finish)

      { offset: offset, crc: crc, compressed: compressed, method: method, flags: flags,
        dos_time: dos_time, dos_date: dos_date, name: name }
    end

    def copy_prepared(out, item, prepared)
      copied = IO.copy_stream(prepared[:part], out)
      raise Error, "Compressed data is incomplete: #{item.name}" unless copied == prepared[:compressed]

      [prepared[:crc], prepared[:compressed]]
    end

    def local_header(name, flags, method, dos_time, dos_date, zip64, crc: 0, compressed: 0, size: 0)
      extra = zip64 ? [ZipArchive::ZIP64_EXTRA_ID, 16, size, compressed].pack('vvQ<Q<') : ''.b
      version = zip64 ? VERSION_ZIP64 : VERSION_DEFAULT
      sizes = zip64 ? [MAX32, MAX32] : [compressed, size]
      [LOCAL_HEADER_SIGNATURE, version, flags, method, dos_time, dos_date, crc, *sizes,
       name.bytesize, extra.bytesize].pack('VvvvvvVVVvv') + name + extra
    end

    def write_data(out, item, method)
      crc = 0
      compressed = 0
      deflater = method == METHOD_DEFLATE ? Zlib::Deflate.new(@level, -Zlib::MAX_WBITS) : nil

      File.open(item.path, 'rb') do |file|
        while (chunk = file.read(CHUNK_SIZE))
          crc = Zlib.crc32(chunk, crc)
          data = deflater ? deflater.deflate(chunk) : chunk
          compressed += out.write(data)
          yield chunk.bytesize
        end
      end
      compressed += out.write(deflater.finish) if deflater
      [crc, compressed]
    ensure
      deflater&.close
    end

    def central_header(item, record)
      zip64_values = []
      size = item.size
      compressed = record[:compressed]
      offset = record[:offset]
      zip64_values << size if size >= MAX32
      zip64_values << compressed if compressed >= MAX32
      zip64_values << offset if offset >= MAX32
      extra = zip64_values.empty? ? ''.b : [ZipArchive::ZIP64_EXTRA_ID, zip64_values.size * 8, *zip64_values].pack("vvQ<#{zip64_values.size}")
      version = zip64_values.empty? ? VERSION_DEFAULT : VERSION_ZIP64
      type = item.directory ? ZipArchive::S_IFDIR : ZipArchive::S_IFREG
      external = ((type | (item.mode & 0o777)) << 16) | (item.directory ? 0x10 : 0)

      [ZipArchive::CENTRAL_HEADER_SIGNATURE, VERSION_MADE_BY, version, record[:flags], record[:method],
       record[:dos_time], record[:dos_date], record[:crc], [compressed, MAX32].min, [size, MAX32].min,
       record[:name].bytesize, extra.bytesize, 0, 0, 0, external, [offset, MAX32].min]
        .pack('VvvvvvvVVVvvvvvVV') + record[:name] + extra
    end

    def write_end_records(out, centrals, count)
      cd_offset = out.pos
      centrals.each { |header| out.write(header) }
      cd_size = out.pos - cd_offset

      if count >= MAX16 || cd_size >= MAX32 || cd_offset >= MAX32
        zip64_offset = out.pos
        out.write([ZipArchive::ZIP64_EOCD_SIGNATURE, 44, VERSION_MADE_BY, VERSION_ZIP64, 0, 0,
                   count, count, cd_size, cd_offset].pack('VQ<vvVVQ<Q<Q<Q<'))
        out.write([ZipArchive::ZIP64_LOCATOR_SIGNATURE, 0, zip64_offset, 1].pack('VVQ<V'))
      end

      out.write([ZipArchive::EOCD_SIGNATURE, 0, 0, [count, MAX16].min, [count, MAX16].min,
                 [cd_size, MAX32].min, [cd_offset, MAX32].min, 0].pack('VvvvvVVv'))
    end

    # DOS 日時は 1980〜2107 年のみ表現できる
    def dos_datetime(time)
      time = time.localtime
      return [0, (1 << 5) | 1] if time.year < 1980

      time = Time.new(2107, 12, 31, 23, 59, 58) if time.year > 2107
      [(time.hour << 11) | (time.min << 5) | (time.sec / 2), ((time.year - 1980) << 9) | (time.month << 5) | time.day]
    end

    def check_cancel!
      raise CancelledError, 'Archive creation cancelled' if @cancelled&.call
    end
  end
end
