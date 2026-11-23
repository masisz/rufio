# frozen_string_literal: true

require 'fiddle'
require_relative 'native_scanner_zig'

module Rufio
  # Zig 実装の画像デコード（別スレッド・GVL 外）。
  #
  # 端末の対応判定・矩形の決定・上限・フォールバックは Ruby 側（TerminalGraphics /
  # ImagePreviewView / GraphicsLayer）が担い、ここでは計算だけを頼む:
  #   ファイルを読む → 形式を判定 → 画素に展開 → 指定ピクセルへ縮小 → PNG に符号化 → Base64
  #
  # ライブラリが無い・古い・`RUFIO_NATIVE_IMAGE=0` のときは available? が false になり、
  # 呼び出し側は PNG 直送（Phase 1 の経路）かテキスト表示に落ちる。
  module NativeImage
    STATE_RUNNING = 0
    STATE_DONE = 1
    STATE_FAILED = 2
    STATE_CANCELLED = 3

    # 端末へ渡す形（Zig 側 image.zig の Format と一致させる）
    FORMAT_PNG = 0
    FORMAT_RGB = 1
    FORMAT_RGBA = 2

    # 判定した形式（Zig 側 image.zig の Kind と一致させる）
    KINDS = { 0 => :png, 1 => :jpeg, 2 => :gif, 3 => :bmp, 255 => :unsupported }.freeze

    # Zig 側と同じ上限（ここでも先に弾く）
    MAX_BYTES = 32 * 1024 * 1024

    class << self
      def available?
        return false if ENV['RUFIO_NATIVE_IMAGE'] == '0'

        NativeScannerZigFFI.image_available?
      end

      # デコードを始める
      # @param path [String] 画像ファイル（絶対パス）
      # @param max_w [Integer] 収めるピクセル幅（0 なら縮小しない）
      # @param max_h [Integer] 収めるピクセル高さ
      # @return [Job, nil] 始められなければ nil
      def decode(path, max_w:, max_h:, format: FORMAT_PNG)
        return nil unless available?

        target = path.to_s
        return nil if target.empty? || target.include?("\0")

        clamped_w = max_w.to_i.clamp(0, 65_535)
        clamped_h = max_h.to_i.clamp(0, 65_535)
        handle = NativeScannerZigFFI.core_image_create(target, target.bytesize,
                                                       clamped_w, clamped_h, format)
        return nil if handle.zero?

        Job.new(handle)
      end

      # 1 セルのピクセル寸法（端末が報告しなければ nil）
      def cell_pixels
        return nil unless available?

        width = Fiddle::Pointer.malloc(4, Fiddle::RUBY_FREE)
        height = Fiddle::Pointer.malloc(4, Fiddle::RUBY_FREE)
        return nil unless NativeScannerZigFFI.core_image_cell_pixels(width, height).zero?

        w = width[0, 4].unpack1('L')
        h = height[0, 4].unpack1('L')
        return nil if w.zero? || h.zero?

        [w, h]
      end
    end

    # 実行中のデコード。ハンドルだけを持ち、結果は done になってから取り出す
    class Job
      def initialize(handle)
        @handle_box = [handle]
        @payload = nil
        @info = nil
        ObjectSpace.define_finalizer(self, self.class.finalizer(@handle_box))
      end

      def self.finalizer(handle_box)
        proc do
          handle = handle_box[0]
          if handle && !handle.zero?
            handle_box[0] = 0
            NativeScannerZigFFI.core_image_destroy(handle)
          end
        end
      end

      def state
        return STATE_FAILED if closed?

        NativeScannerZigFFI.core_image_state(handle)
      end

      def running?
        state == STATE_RUNNING
      end

      def done?
        state == STATE_DONE
      end

      def failed?
        [STATE_FAILED, STATE_CANCELLED].include?(state)
      end

      # @return [Hash, nil] { width:, height:, src_width:, src_height:, channels:, kind: }
      def info
        return @info if @info
        return nil if closed? || !done?

        slots = Array.new(4) { Fiddle::Pointer.malloc(4, Fiddle::RUBY_FREE) }
        channels = Fiddle::Pointer.malloc(1, Fiddle::RUBY_FREE)
        kind = Fiddle::Pointer.malloc(1, Fiddle::RUBY_FREE)
        result = NativeScannerZigFFI.core_image_info(handle, slots[0], slots[1], slots[2], slots[3],
                                                     channels, kind)
        return nil unless result.zero?

        @info = {
          width: slots[0][0, 4].unpack1('L'),
          height: slots[1][0, 4].unpack1('L'),
          src_width: slots[2][0, 4].unpack1('L'),
          src_height: slots[3][0, 4].unpack1('L'),
          channels: channels[0, 1].unpack1('C'),
          kind: KINDS.fetch(kind[0, 1].unpack1('C'), :unsupported)
        }
      end

      # Base64 済みのペイロード（done 以外では nil）。一度取り出したら覚えておく
      def payload
        return @payload if @payload
        return nil if closed? || !done?

        length = Fiddle::Pointer.malloc(8, Fiddle::RUBY_FREE)
        pointer = NativeScannerZigFFI.core_image_payload(handle, length)
        return nil if pointer.null?

        size = length[0, 8].unpack1('J')
        return nil if size.zero?

        @payload = pointer[0, size]
      end

      def cancel
        return if closed?

        NativeScannerZigFFI.core_image_cancel(handle)
      end

      # ハンドルを解放する（実行中のスレッドの終了を待つ）
      def close
        return if closed?

        current = @handle_box[0]
        @handle_box[0] = 0
        ObjectSpace.undefine_finalizer(self)
        NativeScannerZigFFI.core_image_destroy(current)
      end

      def closed?
        h = handle
        h.nil? || h.zero?
      end

      private

      def handle
        @handle_box[0]
      end
    end
  end
end
