# frozen_string_literal: true

require_relative 'image_source'
require_relative 'terminal_graphics'

module Rufio
  # 画像プレビュー。ペインのセルは空白のまま確保し、画素は端末のグラフィックス機能へ渡す
  # （送るのは GraphicsLayer、矩形を決めるのは UIRenderer）。
  #
  # Phase 1 は PNG をそのまま端末に渡す経路だけ。端末が非対応・PNG 以外・大きすぎる
  # ファイルでは画像を出さず、形式と寸法のテキストを見せる（操作は止めない）。
  class ImagePreviewView < PreviewView
    # 直送できるファイルサイズの上限。縮小（Zig）が入るまでは控えめにする
    DIRECT_MAX_BYTES = 8 * 1024 * 1024
    BACK_HINT = 'y: copy path  ESC: back'
    ZOOM_HINT = '+/-: zoom  0: fit'
    PAN_HINT = 'hjkl: pan'
    # ズームは「ペインに収める」= 1.0 を下限に、25% 刻みで 4 倍まで
    ZOOM_STEP = 0.25
    MIN_ZOOM = 1.0
    MAX_ZOOM = 4.0
    # 1 回の移動量（表示している領域に対する割合）
    PAN_STEP = 0.1

    attr_reader :info, :zoom

    def initialize(info, path: nil)
      super(path: path || info&.path)
      @info = info
      reset_zoom
    end

    def image?
      true
    end

    # 端末へ画像を送れるか（送れない理由は status_line に出す）
    def displayable?
      reason.nil?
    end

    # 画像を送れない理由（送れるなら nil）
    def reason
      return 'no image support in this terminal' unless TerminalGraphics.supported?
      return 'unsupported format' unless ImageSource.direct?(@info)
      return 'too large to send' if bytes > DIRECT_MAX_BYTES

      nil
    end

    def bytes
      @info&.bytes.to_i
    end

    # 端末へ渡すバイト列（送れないときは nil）
    def payload
      return nil unless displayable?

      File.binread(@path)
    rescue SystemCallError, IOError
      nil
    end

    # 画像が出せないときにペインへ出す説明（UIRenderer が使う）
    def detail_lines
      lines = ["#{label}  #{dimensions}", format_bytes(bytes)]
      lines << "(#{reason})" if reason
      lines
    end

    def label
      @info ? @info.label : 'image'
    end

    def dimensions
      @info ? @info.dimensions : '?'
    end

    # 例: "PNG 400x300  1.2 MB  125%  |  +/-: zoom  0: fit  hjkl: pan  y: copy path  ESC: back"
    def status_line
      parts = ["#{label} #{dimensions}", format_bytes(bytes)]
      parts << "#{(@zoom * 100).round}%" if zoomed?
      parts << reason if reason
      [parts.join('  '), notice_text || hint].compact.join('  |  ')
    end

    def reset
      reset_zoom
      clear_notice
      true
    end

    # 元画像から切り出して表示する領域 [x, y, 幅, 高さ]。
    # 等倍（ペインに収める）なら nil。拡大時は中央（移動後の位置）を切り出す
    def crop
      return nil unless zoomable? && zoomed?

      width = (@info.width / @zoom).round.clamp(1, @info.width)
      height = (@info.height / @zoom).round.clamp(1, @info.height)
      x = (@info.width * @center_x - width / 2.0).round.clamp(0, @info.width - width)
      y = (@info.height * @center_y - height / 2.0).round.clamp(0, @info.height - height)
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
