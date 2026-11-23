# frozen_string_literal: true

require_relative 'kitty_graphics'
require_relative 'terminal_graphics'

module Rufio
  # 端末に置いた画像の状態を持ち、セル差分描画の後に APC を書き出す層。
  #
  # 描画側（UIRenderer）は毎フレーム request / clear を呼ぶだけで、実際に送るかは
  # ここが決める。前のフレームと同じ画像・同じ位置なら 1 バイトも出さない
  # （静止時のコストを 0 にして、差分描画の方針に合わせる）。
  #
  # Phase 1 は 1 枚だけ扱う。再送条件の追加（行の上書き検知）・デバウンス・
  # キャッシュは Phase 2 で足す。
  class GraphicsLayer
    # 画像 ID は他アプリと衝突しないよう rufio の印と PID から決める
    ID_BASE = 0x5200_0000

    Placement = Struct.new(:key, :payload, :row, :col, :cols, :rows, :format, :pixels,
                           keyword_init: true)

    def initialize(id: nil, passthrough: false)
      @id = id || (ID_BASE | ((Process.pid & 0xffff) << 8))
      @passthrough = passthrough
      @placed = nil
      @desired = nil
      @failed = nil
    end

    attr_reader :id

    # このフレームで出したい画像を伝える（毎フレーム呼ばれる）
    #
    # @param key [Object] 画像の同一性（パス・mtime・矩形など）
    # @param payload [String, #call] 端末へ送るバイト列。Proc を渡すと、実際に送ると
    #   決まったときだけ呼ばれる（毎フレーム大きなファイルを読まないため）
    # @param row [Integer] 矩形の左上の行（1 始まりの端末座標）
    # @param col [Integer] 矩形の左上の桁（1 始まりの端末座標）
    def request(key:, payload:, row:, col:, cols:, rows:,
                format: KittyGraphics::FORMAT_PNG, pixels: nil)
      @desired = Placement.new(key: [key, row, col, cols, rows], payload: payload,
                               row: row, col: col, cols: cols, rows: rows,
                               format: format, pixels: pixels)
      true
    end

    # このフレームでは画像を出さない（置いてあれば flush で消える）
    def clear
      @desired = nil
    end

    def placed?
      !@placed.nil?
    end

    # 変化があれば端末へ書く
    # @return [Boolean] 何か書いたか
    def flush(output)
      return false if output.nil?
      return false if @desired.nil? && @placed.nil?
      return false if @desired && @placed && @desired.key == @placed.key
      # 読めなかった画像は、同じものを毎フレーム読み直さない
      return false if @desired && @placed.nil? && @desired.key == @failed

      sequence, placed = sequence_for(@desired)
      # 読めたかどうかは、書けたかに関わらず覚える
      @failed = placed ? nil : @desired&.key
      return false unless write_raw(output, sequence)

      @placed = placed ? @desired : nil
      true
    end

    # 置いてある画像をすべて消す（終了処理・全画面の再描画）
    def clear_all(output)
      @desired = nil
      @placed = nil
      @failed = nil
      write_raw(output, KittyGraphics.delete_all(passthrough: @passthrough))
    end

    private

    def sequence_for(desired)
      sequence = +''
      # 置き換え・削除はどちらも先に消す（同じ ID を上書きしない端末があるため）
      sequence << KittyGraphics.delete(id: @id, passthrough: @passthrough) if @placed
      if desired
        bytes = resolve(desired.payload)
        # 読めなかった画像は置かない（セルは空のままになる）
        return [sequence, false] if bytes.nil? || bytes.empty?

        sequence << KittyGraphics.place_at(row: desired.row, col: desired.col,
                                          id: @id, payload: bytes,
                                          cols: desired.cols, rows: desired.rows,
                                          format: desired.format, pixels: desired.pixels,
                                          passthrough: @passthrough)
      end
      [sequence, true]
    end

    # 送ると決まってから初めてバイト列を用意する
    def resolve(payload)
      payload.respond_to?(:call) ? payload.call : payload
    rescue StandardError
      nil
    end

    # 端末が閉じていても落ちない（画像はおまけの機能なので操作を止めない）
    def write_raw(output, sequence)
      return false if output.nil? || sequence.nil? || sequence.empty?

      output.write(sequence)
      output.flush
      true
    rescue IOError, SystemCallError
      false
    end
  end
end
