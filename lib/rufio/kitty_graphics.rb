# frozen_string_literal: true

module Rufio
  # Kitty グラフィックスプロトコルのシーケンス組み立て。
  #
  # ここは文字列を作るだけで IO を持たない（書き出すのは GraphicsLayer）。
  # 仕様: https://sw.kovidgoyal.net/kitty/graphics-protocol/
  module KittyGraphics
    APC = "\e_G"
    ST = "\e\\"
    # 1 チャンクのペイロード上限（プロトコルの定め）
    CHUNK = 4096

    # f= の値。PNG は端末側がデコードできるので、ファイルをそのまま送れる
    FORMAT_PNG = 100
    FORMAT_RGB = 24
    FORMAT_RGBA = 32
    # Base64 ペイロードに許す文字だけを通し、APC 終了や任意のエスケープ注入を防ぐ
    BASE64_PATTERN = /\A[A-Za-z0-9+\/=]*\z/.freeze

    class << self
      # 画像を転送して表示する（左上は送信時のカーソル位置）
      #
      # @param id [Integer] 画像 ID（削除・置き換えの単位）
      # @param payload [String] 画像のバイト列（Base64 化はここで行う）
      # @param cols [Integer] 収めるセル数（横）
      # @param rows [Integer] 収めるセル数（縦）
      # @param format [Integer] FORMAT_PNG / FORMAT_RGB / FORMAT_RGBA
      # @param pixels [Array(Integer, Integer), nil] 生ピクセルのときの [幅, 高さ]
      # @param passthrough [Boolean] tmux のパススルーで包むか
      # @param crop [Array(Integer, Integer, Integer, Integer), nil] 元画像から切り出す
      #   領域 [x, y, 幅, 高さ]（ズーム）
      # @param encoded [Boolean] payload が既に Base64 済みなら true
      def transmit(id:, payload:, cols: nil, rows: nil, format: FORMAT_PNG, placement: 1,
                   pixels: nil, crop: nil, chunk: CHUNK, passthrough: false, encoded: false)
        data = encoded ? payload.to_s : [payload.to_s].pack('m0')
        return '' if encoded && !BASE64_PATTERN.match?(data)

        pieces = split(data, chunk)
        control = control_keys(id: id, cols: cols, rows: rows, format: format,
                               placement: placement, pixels: pixels, crop: crop)

        pieces.each_with_index.map do |piece, index|
          keys = if index.zero?
                   pieces.length > 1 ? "#{control},m=1" : control
                 else
                   index == pieces.length - 1 ? 'm=0' : 'm=1'
                 end
          sequence("#{keys};#{piece}", passthrough: passthrough)
        end.join
      end

      # カーソルを矩形の左上（1 始まり）へ動かしてから送り、カーソルを戻す。
      # C=1 を付けているのでカーソルは動かないが、位置の起点をはっきりさせる
      def place_at(row:, col:, passthrough: false, **options)
        body = transmit(passthrough: passthrough, **options)
        return '' if body.empty?

        move = "\e[#{row.to_i};#{col.to_i}H"
        "#{move}#{body}\e[H"
      end

      # 既に送った画像を、送り直さずに今のカーソル位置へ置く
      def place(id:, cols:, rows:, placement: 1, passthrough: false)
        keys = ['a=p', "i=#{id.to_i}", "p=#{placement.to_i}", "c=#{cols.to_i}", "r=#{rows.to_i}", 'C=1', 'q=2']
        sequence(keys.join(','), passthrough: passthrough)
      end

      def delete(id:, passthrough: false)
        sequence("a=d,d=i,i=#{id.to_i},q=2", passthrough: passthrough)
      end

      def delete_all(passthrough: false)
        sequence('a=d,d=A,q=2', passthrough: passthrough)
      end

      # 対応判定用の問い合わせ（1x1 の RGB を送って応答だけを見る）
      def query(id:, passthrough: false)
        sequence("i=#{id.to_i},s=1,v=1,a=q,t=d,f=24;AAAA", passthrough: passthrough)
      end

      # 応答が「この問い合わせへの OK」かどうか
      def ok?(response, id:)
        response.to_s.include?("_Gi=#{id};OK")
      end

      private

      def control_keys(id:, cols:, rows:, format:, placement:, pixels:, crop: nil)
        keys = ['a=T', "f=#{format.to_i}", 't=d', "i=#{id.to_i}", "p=#{placement.to_i}"]
        # c / r を両方省略すると端末は画像の元ピクセル（元アスペクト比）のまま描画する
        keys << "c=#{cols.to_i}" if cols && cols.to_i.positive?
        keys << "r=#{rows.to_i}" if rows && rows.to_i.positive?
        keys.concat(['C=1', 'q=2'])
        if pixels
          keys << "s=#{pixels[0].to_i}"
          keys << "v=#{pixels[1].to_i}"
        end
        if crop
          # 元画像の一部だけを同じセル矩形に出す（ズーム）
          keys << "x=#{crop[0].to_i}"
          keys << "y=#{crop[1].to_i}"
          keys << "w=#{crop[2].to_i}"
          keys << "h=#{crop[3].to_i}"
        end
        keys.join(',')
      end

      def split(encoded, chunk)
        size = [chunk.to_i, 1].max
        return [''] if encoded.empty?

        (0...encoded.bytesize).step(size).map { |offset| encoded.byteslice(offset, size) }
      rescue RangeError
        ['']
      end

      # tmux の中では ESC を二重にして DCS パススルーで包む
      # （tmux 3.3+ かつ allow-passthrough on が必要）
      def sequence(body, passthrough:)
        raw = "#{APC}#{body}#{ST}"
        return raw unless passthrough

        "\ePtmux;#{raw.gsub("\e", "\e\e")}#{ST}"
      end
    end
  end
end
