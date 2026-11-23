# frozen_string_literal: true

module Rufio
  # 画像ファイルの形式と寸法を、見出し（先頭の数十バイト）だけから読む。
  #
  # 判定は拡張子ではなくシグネチャで行う（`.png` という名前の別形式を端末へ送らない）。
  # 画素は読まないので Ruby だけで完結し、デコードが要る処理は Zig 側（Phase 3）に回す。
  class ImageSource
    # JPEG はマーカーを辿るため、見出しとして読む上限を決めておく
    HEADER_BYTES = 64 * 1024

    SIGNATURES = {
      png: "\x89PNG\r\n\x1a\n".b,
      jpeg: "\xff\xd8".b,
      gif: 'GIF8'.b,
      bmp: 'BM'.b
    }.freeze

    # 寸法を持たない JPEG のフレーム以外のマーカー（長さを読んで飛ばす）
    JPEG_SOF_MARKERS = [0xc0, 0xc1, 0xc2, 0xc3, 0xc5, 0xc6, 0xc7,
                        0xc9, 0xca, 0xcb, 0xcd, 0xce, 0xcf].freeze

    Info = Struct.new(:path, :kind, :width, :height, :bytes, keyword_init: true) do
      # 画面に出す形式名（"PNG" / "JPEG" ...）
      def label
        kind.to_s.upcase
      end

      def dimensions?
        width.to_i.positive? && height.to_i.positive?
      end

      def dimensions
        dimensions? ? "#{width}x#{height}" : '?'
      end
    end

    class << self
      # @return [Boolean] 画像として扱える形式か
      def supports?(path)
        !kind(path).nil?
      end

      # @return [Symbol, nil] :png / :jpeg / :gif / :bmp（判定できなければ nil）
      def kind(path)
        header = read_header(path, 8)
        return nil if header.nil? || header.empty?

        SIGNATURES.each { |name, signature| return name if header.start_with?(signature) }
        nil
      end

      # @return [Info, nil] 形式が分かれば Info（寸法が読めない場合も Info を返す）
      def read(path)
        header = read_header(path, HEADER_BYTES)
        return nil if header.nil? || header.empty?

        name, = SIGNATURES.find { |_, signature| header.start_with?(signature) }
        return nil unless name

        width, height = dimensions(name, header)
        Info.new(path: path, kind: name, width: width, height: height, bytes: file_size(path))
      end

      # 端末がそのままデコードできる形式か（Kitty は PNG を自前で読める）
      def direct?(info)
        return false unless info

        info.kind == :png
      end

      private

      def read_header(path, length)
        return nil unless File.file?(path)

        File.binread(path, length)
      rescue SystemCallError, IOError
        nil
      end

      def file_size(path)
        File.size(path)
      rescue SystemCallError
        0
      end

      def dimensions(kind, header)
        case kind
        when :png then png_dimensions(header)
        when :jpeg then jpeg_dimensions(header)
        when :gif then gif_dimensions(header)
        when :bmp then bmp_dimensions(header)
        end || [0, 0]
      end

      # IHDR は必ず先頭チャンク。幅・高さはビッグエンディアンの 32bit
      def png_dimensions(header)
        return nil unless header.bytesize >= 24 && header.byteslice(12, 4) == 'IHDR'

        header.byteslice(16, 8).unpack('N2')
      end

      # 論理画面記述子（6 バイト目から）はリトルエンディアンの 16bit
      def gif_dimensions(header)
        return nil unless header.bytesize >= 10

        header.byteslice(6, 4).unpack('v2')
      end

      # DIB ヘッダの幅・高さはリトルエンディアンの符号付き 32bit
      # （高さが負なら上から下へ並ぶ画像。寸法としては絶対値を使う）
      def bmp_dimensions(header)
        return nil unless header.bytesize >= 26

        width, height = header.byteslice(18, 8).unpack('l<2')
        [width.abs, height.abs]
      end

      # SOI の後ろからマーカーを辿り、最初のフレーム（SOFn）の寸法を読む
      def jpeg_dimensions(header)
        offset = 2
        size = header.bytesize
        while offset + 4 <= size
          # マーカーは 0xff で始まる。0xff の連続は詰め物なので読み飛ばす
          unless header.getbyte(offset) == 0xff
            offset += 1
            next
          end

          marker = header.getbyte(offset + 1)
          break if marker.nil?
          if marker == 0xff
            offset += 1
            next
          end

          # 長さを持たないマーカー（RSTn / SOI / EOI / TEM）
          if (0xd0..0xd9).cover?(marker) || marker == 0x01
            offset += 2
            next
          end

          length = header.byteslice(offset + 2, 2)&.unpack1('n')
          break if length.nil? || length < 2

          if JPEG_SOF_MARKERS.include?(marker) && offset + 9 <= size
            height, width = header.byteslice(offset + 5, 4).unpack('n2')
            return [width, height]
          end

          offset += 2 + length
        end
        nil
      end
    end
  end
end
