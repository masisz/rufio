# frozen_string_literal: true

require 'zlib'

module Rufio
  # ZIPアーカイブの読み取り専用パーサー（FastZip Phase 1: Pure Ruby 実装）
  #
  # EOCD → (ZIP64 EOCD) → Central Directory の順に辿り、
  # ファイル本体を展開せずにエントリ一覧（unzip -l 相当）を取得する。
  # 将来の Zig ネイティブ実装はこのクラスと同じ結果を返すことを互換条件とする。
  class ZipArchive
    class FormatError < StandardError; end

    Entry = Struct.new(
      :name, :compressed_size, :size, :method, :crc32, :mtime,
      :local_header_offset, :flags, :directory, :encrypted,
      :version_made_by, :external_attributes,
      keyword_init: true
    ) do
      alias_method :directory?, :directory
      alias_method :encrypted?, :encrypted

      # Unix 系で作られたエントリのファイルモード（それ以外は nil）
      def unix_mode
        return nil unless (version_made_by >> 8) == HOST_UNIX

        mode = external_attributes >> 16
        mode.zero? ? nil : mode
      end

      def symlink?
        mode = unix_mode
        !mode.nil? && (mode & S_IFMT) == S_IFLNK
      end
    end

    Listing = Struct.new(:entries, :total_entries, :comment, :zip64, :central_directory_offset, keyword_init: true) do
      alias_method :zip64?, :zip64

      def truncated?
        entries.length < total_entries
      end
    end

    EOCD_SIGNATURE = 0x06054b50
    ZIP64_EOCD_SIGNATURE = 0x06064b50
    ZIP64_LOCATOR_SIGNATURE = 0x07064b50
    CENTRAL_HEADER_SIGNATURE = 0x02014b50

    EOCD_SIZE = 22
    ZIP64_LOCATOR_SIZE = 20
    ZIP64_EOCD_MIN_SIZE = 56
    CENTRAL_HEADER_SIZE = 46
    MAX_COMMENT_SIZE = 0xFFFF

    ZIP64_EXTRA_ID = 0x0001
    UNICODE_PATH_EXTRA_ID = 0x7075

    FLAG_ENCRYPTED = 0x0001
    FLAG_UTF8 = 0x0800

    HOST_UNIX = 3
    S_IFMT = 0o170000
    S_IFLNK = 0o120000
    S_IFDIR = 0o040000
    S_IFREG = 0o100000

    METHOD_NAMES = {
      0 => 'Stored',
      8 => 'Deflate',
      9 => 'Deflate64',
      12 => 'BZip2',
      14 => 'LZMA',
      93 => 'Zstd',
      95 => 'XZ',
      99 => 'AES'
    }.freeze

    def self.method_name(method)
      METHOD_NAMES.fetch(method, "Method#{method}")
    end

    # ZIPのマジックナンバーで始まるか（空アーカイブはEOCDから始まる）
    def self.zip_signature?(path)
      head = File.binread(path, 4)
      ["PK\x03\x04".b, "PK\x05\x06".b].include?(head)
    rescue SystemCallError
      false
    end

    # @param path [String] ZIPファイルのパス
    # @param limit [Integer, nil] 読み取るエントリ数の上限（プレビュー用）
    # @return [Listing]
    def self.list(path, limit: nil)
      new(path).list(limit: limit)
    end

    def initialize(path)
      @path = path
    end

    def list(limit: nil)
      File.open(@path, 'rb') do |io|
        file_size = io.size
        eocd = read_end_of_central_directory(io, file_size)
        count = limit ? [eocd[:total_entries], limit].min : eocd[:total_entries]
        entries = read_central_directory(io, file_size, eocd, count)

        Listing.new(
          entries: entries,
          total_entries: eocd[:total_entries],
          comment: eocd[:comment],
          zip64: eocd[:zip64],
          central_directory_offset: eocd[:cd_offset]
        )
      end
    end

    private

    # ファイル末尾から EOCD を後方探索する
    def read_end_of_central_directory(io, file_size)
      raise FormatError, 'File too small to be a ZIP archive' if file_size < EOCD_SIZE

      tail_size = [file_size, EOCD_SIZE + MAX_COMMENT_SIZE].min
      tail_offset = file_size - tail_size
      tail = read_at(io, tail_offset, tail_size)

      position = find_eocd_position(io, tail)
      raise FormatError, 'End of central directory not found' unless position

      fields = tail.byteslice(position, EOCD_SIZE).unpack('VvvvvVVv')
      _sig, disk, cd_disk, _disk_entries, total_entries, cd_size, cd_offset, comment_length = fields
      comment = tail.byteslice(position + EOCD_SIZE, comment_length)
      eocd = {
        total_entries: total_entries,
        cd_size: cd_size,
        cd_offset: cd_offset,
        comment: decode_text(comment, utf8: false),
        zip64: false
      }

      if zip64_required?(fields)
        apply_zip64_eocd(io, tail_offset + position, eocd)
      elsif disk != 0 || cd_disk != 0
        raise FormatError, 'Multi-disk ZIP archives are not supported'
      end

      eocd
    end

    # コメント長と整合し、指す先に Central Directory がある最後の EOCD を探す
    # （コメント内に EOCD と同じバイト列が含まれていても誤認しない）
    def find_eocd_position(io, tail)
      signature = [EOCD_SIGNATURE].pack('V')
      position = tail.bytesize - EOCD_SIZE

      while position >= 0
        position = tail.rindex(signature, position)
        return nil unless position

        return position if plausible_eocd?(io, tail, position)

        position -= 1
      end

      nil
    end

    def plausible_eocd?(io, tail, position)
      fields = tail.byteslice(position, EOCD_SIZE).unpack('VvvvvVVv')
      return false unless position + EOCD_SIZE + fields[7] == tail.bytesize
      return true if fields[4].zero? || zip64_required?(fields)

      io.seek(fields[6])
      io.read(4)&.unpack1('V') == CENTRAL_HEADER_SIGNATURE
    end

    def zip64_required?(fields)
      fields[1..4].any? { |v| v == 0xFFFF } || fields[5] == 0xFFFFFFFF || fields[6] == 0xFFFFFFFF
    end

    def apply_zip64_eocd(io, eocd_offset, eocd)
      locator_offset = eocd_offset - ZIP64_LOCATOR_SIZE
      raise FormatError, 'ZIP64 locator not found' if locator_offset.negative?

      sig, _disk, zip64_eocd_offset, _total_disks = read_at(io, locator_offset, ZIP64_LOCATOR_SIZE).unpack('VVQ<V')
      raise FormatError, 'ZIP64 locator not found' unless sig == ZIP64_LOCATOR_SIGNATURE

      record = read_at(io, zip64_eocd_offset, ZIP64_EOCD_MIN_SIZE)
      sig, _size, _made, _needed, _disk, _cd_disk, _disk_entries, total_entries, cd_size, cd_offset =
        record.unpack('VQ<vvVVQ<Q<Q<Q<')
      raise FormatError, 'ZIP64 end of central directory not found' unless sig == ZIP64_EOCD_SIGNATURE

      eocd.merge!(total_entries: total_entries, cd_size: cd_size, cd_offset: cd_offset, zip64: true)
    end

    def read_central_directory(io, file_size, eocd, count)
      cd_end = eocd[:cd_offset] + eocd[:cd_size]
      raise FormatError, 'Central directory is out of range' if cd_end > file_size

      offset = eocd[:cd_offset]
      Array.new(count) do
        raise FormatError, 'Central directory is truncated' if offset + CENTRAL_HEADER_SIZE > cd_end

        entry, offset = read_central_header(io, offset, cd_end)
        entry
      end
    end

    def read_central_header(io, offset, cd_end)
      header = read_at(io, offset, CENTRAL_HEADER_SIZE)
      sig, made_by, _needed, flags, method, dos_time, dos_date, crc32, compressed_size, size,
        name_length, extra_length, comment_length, _disk, _int_attr, ext_attr, local_offset =
        header.unpack('VvvvvvvVVVvvvvvVV')
      raise FormatError, "Invalid central directory header at offset #{offset}" unless sig == CENTRAL_HEADER_SIGNATURE

      variable_length = name_length + extra_length + comment_length
      next_offset = offset + CENTRAL_HEADER_SIZE + variable_length
      raise FormatError, 'Central directory is truncated' if next_offset > cd_end

      variable = read_at(io, offset + CENTRAL_HEADER_SIZE, name_length + extra_length)
      raw_name = variable.byteslice(0, name_length)
      extra = parse_extra_fields(variable.byteslice(name_length, extra_length))

      sizes = { size: size, compressed_size: compressed_size, local_header_offset: local_offset }
      apply_zip64_extra(sizes, extra[ZIP64_EXTRA_ID]) if extra[ZIP64_EXTRA_ID]

      name = unicode_path(extra[UNICODE_PATH_EXTRA_ID], raw_name) ||
             decode_text(raw_name, utf8: (flags & FLAG_UTF8) != 0)

      entry = Entry.new(
        name: name,
        compressed_size: sizes[:compressed_size],
        size: sizes[:size],
        method: method,
        crc32: crc32,
        mtime: dos_to_time(dos_date, dos_time),
        local_header_offset: sizes[:local_header_offset],
        flags: flags,
        directory: name.end_with?('/'),
        encrypted: (flags & FLAG_ENCRYPTED) != 0,
        version_made_by: made_by,
        external_attributes: ext_attr
      )
      [entry, next_offset]
    end

    def parse_extra_fields(data)
      fields = {}
      pos = 0
      while pos + 4 <= data.bytesize
        id, length = data.byteslice(pos, 4).unpack('vv')
        break if pos + 4 + length > data.bytesize

        fields[id] ||= data.byteslice(pos + 4, length)
        pos += 4 + length
      end
      fields
    end

    # ZIP64 拡張フィールドには 0xFFFFFFFF だった値だけが既定の順序で格納される
    def apply_zip64_extra(sizes, data)
      pos = 0
      %i[size compressed_size local_header_offset].each do |key|
        next unless sizes[key] == 0xFFFFFFFF
        break if pos + 8 > data.bytesize

        sizes[key] = data.byteslice(pos, 8).unpack1('Q<')
        pos += 8
      end
    end

    # Info-ZIP Unicode Path 拡張（元のファイル名のCRCが一致する場合のみ採用）
    def unicode_path(data, raw_name)
      return nil if data.nil? || data.bytesize < 5

      version, name_crc = data.unpack('CV')
      return nil unless version == 1 && name_crc == Zlib.crc32(raw_name)

      name = data.byteslice(5..).force_encoding(Encoding::UTF_8)
      name.valid_encoding? ? name : nil
    end

    # UTFフラグがなければ UTF-8 → CP932（Windows日本語環境で作られたZIP）→ 置換 の順で解釈する
    def decode_text(raw, utf8:)
      text = raw.dup.force_encoding(Encoding::UTF_8)
      return text if utf8 || text.valid_encoding?

      raw.encode(Encoding::UTF_8, Encoding::Windows_31J)
    rescue EncodingError
      raw.encode(Encoding::UTF_8, Encoding::BINARY, invalid: :replace, undef: :replace, replace: '?')
    end

    def dos_to_time(date, time)
      return nil if date.zero?

      Time.new(
        ((date >> 9) & 0x7F) + 1980, (date >> 5) & 0x0F, date & 0x1F,
        (time >> 11) & 0x1F, (time >> 5) & 0x3F, (time & 0x1F) * 2
      )
    rescue ArgumentError
      nil
    end

    def read_at(io, offset, length)
      io.seek(offset)
      data = io.read(length)
      raise FormatError, 'Unexpected end of file' if data.nil? || data.bytesize < length

      data
    end
  end
end
