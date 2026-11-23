# frozen_string_literal: true

require_relative 'image_source'
require_relative 'terminal_graphics'
require_relative 'kitty_graphics'
require_relative 'native_image'

module Rufio
  # 画像プレビュー。ペインのセルは空白のまま確保し、画素は端末のグラフィックス機能へ渡す
  # （送るのは GraphicsLayer、矩形を決めるのは UIRenderer）。
  #
  # 端末へ渡す経路は 2 つ:
  # - ネイティブ（Zig）が使えるとき: PNG / JPEG / BMP をペインの実ピクセルへ縮小して
  #   PNG に符号化し直す。転送量が小さく、読み込み上限も大きい
  # - 使えないとき: PNG のファイルをそのまま渡す（端末が自前でデコードする）
  #
  # どちらも無理な場合（非対応端末・GIF など・大きすぎる）は画像を出さず、形式と
  # 寸法のテキストを見せる（操作は止めない）。
  class ImagePreviewView < PreviewView
    # 直送できるファイルサイズの上限（ネイティブが使えないときの経路）
    DIRECT_MAX_BYTES = 8 * 1024 * 1024
    # ネイティブで読む上限（Zig 側と同じ）
    NATIVE_MAX_BYTES = NativeImage::MAX_BYTES
    # ネイティブでデコードできる形式
    NATIVE_KINDS = %i[png jpeg bmp].freeze

    BACK_HINT = 'y: copy path  ESC: back'
    ZOOM_HINT = '+/-: zoom  0: fit'
    PAN_HINT = 'hjkl: pan'
    # ズームは「ペインに収める」= 1.0 を下限に、25% 刻みで 4 倍まで
    ZOOM_STEP = 0.25
    MIN_ZOOM = 1.0
    MAX_ZOOM = 4.0
    # 1 回の移動量（表示している領域に対する割合）
    PAN_STEP = 0.1
    # ペインのピクセルが分からないときの既定（セル 8x16 相当）
    DEFAULT_TARGET_PIXELS = [640, 320].freeze

    attr_reader :info, :zoom

    def initialize(info, path: nil)
      super(path: path || info&.path)
      @info = info
      @target_pixels = DEFAULT_TARGET_PIXELS
      @job = nil
      @job_key = nil
      @decoded = nil
      reset_zoom
    end

    def image?
      true
    end

    # 描画側が毎フレーム伝えるペインの実ピクセル（[幅, 高さ]）
    def target_pixels=(size)
      return if size.nil?

      width = size[0].to_i
      height = size[1].to_i
      return if width <= 0 || height <= 0

      @target_pixels = [width, height]
    end

    # 端末へ画像を送れるか（送れない理由は status_line に出す）
    def displayable?
      reason.nil?
    end

    # 画像を送れない理由（送れるなら nil）
    def reason
      return 'no image support in this terminal' unless TerminalGraphics.supported?
      return nil if native?
      return 'unsupported format' unless ImageSource.direct?(@info)
      return 'too large to send' if bytes > DIRECT_MAX_BYTES

      nil
    end

    # ネイティブでデコードして送る経路を使うか
    def native?
      return false if @native_failed
      return false unless NativeImage.available?
      return false unless @info && NATIVE_KINDS.include?(@info.kind)
      return false if bytes > NATIVE_MAX_BYTES

      true
    end

    # デコード待ちか（この間は画像を送らず「decoding」と出す）
    def loading?
      return false unless displayable? && native?

      start_decode
      @decoded.nil? && !@job.nil? && @job.running?
    end

    # 端末へ渡すもの。まだ用意できていなければ nil
    # @return [Hash, nil] { key:, payload:, encoded:, format:, pixels: }
    def transfer
      return nil unless displayable?

      native? ? native_transfer : direct_transfer
    end

    # 端末へ渡した画像の寸法（切り出しの基準）
    def transmitted_size
      return @decoded[:size] if @decoded
      return [@info.width, @info.height] if @info&.dimensions?

      [0, 0]
    end

    def bytes
      @info&.bytes.to_i
    end

    # 画像が出せないときにペインへ出す説明（UIRenderer が使う）
    def detail_lines
      lines = ["#{label}  #{dimensions}", format_bytes(bytes)]
      lines << "(#{reason})" if reason
      lines
    end

    # デコード中にペインへ出す行
    def loading_lines
      ["#{label}  #{dimensions}", format_bytes(bytes), '(decoding...)']
    end

    def label
      @info ? @info.label : 'image'
    end

    def dimensions
      @info ? @info.dimensions : '?'
    end

    # 例: "PNG 400x300  1.2 MB  → 640x480  125%  |  +/-: zoom  0: fit  ESC: back"
    def status_line
      parts = ["#{label} #{dimensions}", format_bytes(bytes)]
      parts << "decoding..." if loading?
      parts << "→ #{@decoded[:size].join('x')}" if @decoded && !loading?
      parts << "#{(@zoom * 100).round}%" if zoomed?
      parts << reason if reason
      [parts.join('  '), notice_text || hint].compact.join('  |  ')
    end

    def reset
      reset_zoom
      clear_notice
      true
    end

    # ビューを捨てるときに呼ぶ（デコード中のジョブを片付け、以後は何も始めない）
    def release
      @released = true
      drop_job
      true
    end

    # 元画像から切り出して表示する領域 [x, y, 幅, 高さ]（転送した画像の座標）。
    # 等倍（ペインに収める）なら nil
    def crop
      return nil unless zoomable? && zoomed?

      size = transmitted_size
      return nil if size[0].zero? || size[1].zero?

      width = (size[0] / @zoom).round.clamp(1, size[0])
      height = (size[1] / @zoom).round.clamp(1, size[1])
      x = (size[0] * @center_x - width / 2.0).round.clamp(0, size[0] - width)
      y = (size[1] * @center_y - height / 2.0).round.clamp(0, size[1] - height)
      [x, y, width, height]
    end

    def zoomed?
      @zoom > MIN_ZOOM
    end

    # ズームできるのは、画像を出せて寸法が分かっているときだけ
    def zoomable?
      displayable? && @info&.dimensions?
    end

    # y（コピー）に加えて、ズームと移動を扱う
    def handle_key(key)
      return super unless zoomable?

      case key
      when '+', '=' then zoom_by(ZOOM_STEP)
      when '-', '_' then zoom_by(-ZOOM_STEP)
      when '0' then zoom_to(MIN_ZOOM)
      when 'l', "\e[C" then pan(1, 0)
      when 'h', "\e[D" then pan(-1, 0)
      when 'j', "\e[B" then pan(0, 1)
      when 'k', "\e[A" then pan(0, -1)
      else super
      end
    end

    private

    # === 端末へ渡すもの ===

    # PNG をそのまま渡す（ネイティブが使えないとき）
    def direct_transfer
      {
        key: [@path, mtime],
        payload: -> { read_file },
        encoded: false,
        format: KittyGraphics::FORMAT_PNG,
        pixels: nil
      }
    end

    # ネイティブで縮小・符号化した PNG を渡す
    def native_transfer
      start_decode
      return nil if @decoded.nil?

      {
        key: @decoded[:key],
        payload: @decoded[:payload],
        encoded: true,
        format: KittyGraphics::FORMAT_PNG,
        pixels: nil
      }
    end

    def read_file
      File.binread(@path)
    rescue SystemCallError, IOError
      nil
    end

    # === デコード ===

    # 目標ピクセル。ズーム中はその倍率で細かくデコードする（切り出しても粗くならない）
    def decode_target
      width = (@target_pixels[0] * @zoom).round
      height = (@target_pixels[1] * @zoom).round
      return [width, height] unless @info&.dimensions?

      [[width, @info.width].min, [height, @info.height].min]
    end

    def decode_key
      [@path, mtime, decode_target]
    end

    # 目標が変わっていれば取り直す。終わっていれば結果を取り込む
    def start_decode
      return if @released

      key = decode_key
      if @job_key != key
        drop_job
        @job_key = key
        @job = NativeImage.decode(@path, max_w: key[2][0], max_h: key[2][1])
        return if @job.nil?
      end

      return if @job.nil? || @decoded

      if @job.done?
        payload = @job.payload
        info = @job.info
        @decoded = { key: key, payload: payload, size: [info[:width], info[:height]] } if payload && info
      elsif @job.failed?
        # デコードできなかった画像は、以後ネイティブ経路を使わない
        @job.close
        @job = nil
        @native_failed = true
      end
    end

    def drop_job
      @job&.cancel
      @job&.close
      @job = nil
      @job_key = nil
      @decoded = nil
    end

    def mtime
      File.mtime(@path).to_i
    rescue SystemCallError
      0
    end

    # === 表示 ===

    def hint
      return BACK_HINT unless zoomable?

      hints = [ZOOM_HINT]
      hints << PAN_HINT if zoomed?
      "#{hints.join('  ')}  #{BACK_HINT}"
    end

    def reset_zoom
      @zoom = MIN_ZOOM
      @center_x = 0.5
      @center_y = 0.5
    end

    def zoom_by(delta)
      zoom_to(@zoom + delta)
    end

    def zoom_to(value)
      target = value.clamp(MIN_ZOOM, MAX_ZOOM)
      return false if (target - @zoom).abs < Float::EPSILON

      @zoom = target
      # 収まりに戻したら移動も戻す
      reset_center unless zoomed?
      clear_notice
      true
    end

    def reset_center
      @center_x = 0.5
      @center_y = 0.5
    end

    # 表示している領域の PAN_STEP 分ずつ動かし、画像の外に出ないようにする
    def pan(dx, dy)
      return false unless zoomed?

      visible = 1.0 / @zoom
      margin = visible / 2.0
      before = [@center_x, @center_y]
      @center_x = (@center_x + dx * visible * PAN_STEP).clamp(margin, 1.0 - margin)
      @center_y = (@center_y + dy * visible * PAN_STEP).clamp(margin, 1.0 - margin)
      before != [@center_x, @center_y]
    end

    def format_bytes(size)
      units = [[1024 * 1024 * 1024, 'GB'], [1024 * 1024, 'MB'], [1024, 'KB']]
      units.each do |limit, suffix|
        return "#{(size.to_f / limit).round(1)} #{suffix}" if size >= limit
      end
      "#{size} B"
    end
  end
end
