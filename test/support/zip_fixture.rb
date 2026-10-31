# frozen_string_literal: true

require 'zlib'

# テスト用の最小ZIPライタ（外部コマンドに依存せず、壊れた・悪意のあるアーカイブも作れる）
class ZipFixture
  def initialize
    @locals = []
    @centrals = []
    @offset = 0
  end

  # unix_mode: Unix 系で作られたエントリとしてファイルモードを入れる
  # crc / size / local_offset: 壊れたアーカイブを作るための上書き
  def add(raw_name, data, deflate: false, flags: 0, extra: ''.b, time: Time.new(2026, 10, 31, 12, 34, 56),
          unix_mode: nil, crc: nil, size: nil, local_offset: nil)
    raw_name = raw_name.b
    payload = deflate ? Zlib::Deflate.new(Zlib::DEFAULT_COMPRESSION, -Zlib::MAX_WBITS).then { |z| z.deflate(data, Zlib::FINISH) } : data.b
    method = deflate ? 8 : 0
    crc ||= Zlib.crc32(data)
    size ||= data.bytesize
    dos_time = (time.hour << 11) | (time.min << 5) | (time.sec / 2)
    dos_date = ((time.year - 1980) << 9) | (time.month << 5) | time.day
    made_by = unix_mode ? (3 << 8) | 20 : 20
    external = unix_mode ? unix_mode << 16 : 0

    local = [0x04034b50, 20, flags, method, dos_time, dos_date, crc, payload.bytesize, size,
             raw_name.bytesize, 0].pack('VvvvvvVVVvv') + raw_name + payload
    central = [0x02014b50, made_by, 20, flags, method, dos_time, dos_date, crc, payload.bytesize, size,
               raw_name.bytesize, extra.bytesize, 0, 0, 0, external, local_offset || @offset]
              .pack('VvvvvvvVVVvvvvvVV') + raw_name + extra
    @locals << local unless local_offset
    @centrals << central
    @offset += local.bytesize unless local_offset
    self
  end

  def to_s(comment: '')
    cd = @centrals.join
    eocd = [0x06054b50, 0, 0, @centrals.size, @centrals.size, cd.bytesize, @offset, comment.bytesize].pack('VvvvvVVv')
    @locals.join + cd + eocd + comment.b
  end
end
