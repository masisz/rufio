# frozen_string_literal: true

module Rufio
  # ターミナルからのマルチバイト入力（UTF-8）を読み込むクラス。
  # read_nonblock(1) は1バイトずつしか読まないため、日本語などのマルチバイト文字が
  # 複数のイベントに分割される問題を解決する。
  class MultibyteInputReader
    def initialize(io = STDIN)
      @io = io
    end

    # 1文字（マルチバイト対応）を読み込む。
    # 読み込めない場合は nil を返す。
    def read_char
      byte = @io.read_nonblock(1)
      return nil if byte.nil?

      remaining = utf8_remaining_bytes(byte.ord)
      return byte.force_encoding(Encoding::UTF_8) if remaining == 0

      buf = byte.b
      remaining.times do
        next_byte = @io.read_nonblock(1)
        return nil if next_byte.nil?

        buf << next_byte.b
      end

      result = buf.force_encoding(Encoding::UTF_8)
      result.valid_encoding? ? result : nil
    rescue IO::WaitReadable, IO::EAGAINWaitReadable, EOFError
      nil
    end

    private

    def utf8_remaining_bytes(byte_val)
      case byte_val
      when 0x00..0x7F then 0  # ASCII（ESC 0x1B を含む）
      when 0xC0..0xDF then 1  # 2バイト文字
      when 0xE0..0xEF then 2  # 3バイト文字（日本語など）
      when 0xF0..0xF7 then 3  # 4バイト文字（絵文字など）
      else 0
      end
    end
  end
end
