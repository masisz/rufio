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

    attr_reader :info

    def initialize(info, path: nil)
      super(path: path || info&.path)
      @info = info
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

    # 例: "PNG 400x300  1.2 MB  |  y: copy path  ESC: back"
    def status_line
      parts = ["#{label} #{dimensions}", format_bytes(bytes)]
      parts << reason if reason
      [parts.join('  '), notice_text || BACK_HINT].compact.join('  |  ')
    end

    def reset
      clear_notice
      true
    end

    # y（コピー）だけを扱う。スクロールも検索もしない
    def handle_key(key)
      super
    end

    private

    def format_bytes(size)
      units = [[1024 * 1024 * 1024, 'GB'], [1024 * 1024, 'MB'], [1024, 'KB']]
      units.each do |limit, suffix|
        return "#{(size.to_f / limit).round(1)} #{suffix}" if size >= limit
      end
      "#{size} B"
    end
  end
end
