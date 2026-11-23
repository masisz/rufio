# frozen_string_literal: true

require_relative 'kitty_graphics'
require_relative 'terminal_graphics'

module Rufio
  # 端末に置いた画像の状態を持ち、セル差分描画の後に APC を書き出す層。
  #
  # 描画側（UIRenderer）は毎フレーム request / clear を呼ぶだけで、実際に送るかは
  # ここが決める。前のフレームと同じ画像・同じ位置で、矩形の中が書き換えられても
  # いなければ 1 バイトも出さない（静止時のコストを 0 にして、差分描画の方針に合わせる）。
  #
  # 送る条件:
  # - 置いていない画像を頼まれた（別のファイルへ移ったときは少し待つ = デバウンス）
  # - 置き場所・切り出し（ズーム）が変わった
  # - 置いてある矩形の中のセルが書き換えられた（通知やモード切替で画像が削れたとき）
  class GraphicsLayer
    # 画像 ID は他アプリと衝突しないよう rufio の印と PID から決める
    ID_BASE = 0x5200_0000
    # 別のファイルへ移ってから送るまでの待ち（j/k の連打で MB 級の転送を繰り返さない）
    DEFAULT_DEBOUNCE = 0.08
    # 覚えておく画像の枚数と合計バイト数（Base64 後）
    DEFAULT_CACHE_ENTRIES = 4
    DEFAULT_CACHE_BYTES = 8 * 1024 * 1024

    Placement = Struct.new(:source, :key, :payload, :row, :col, :cols, :rows,
                           :format, :pixels, :crop, keyword_init: true)

    attr_reader :id

    def initialize(id: nil, passthrough: false, debounce: DEFAULT_DEBOUNCE,
                   cache_entries: DEFAULT_CACHE_ENTRIES, cache_bytes: DEFAULT_CACHE_BYTES)
      @id = id || (ID_BASE | ((Process.pid & 0xffff) << 8))
      @passthrough = passthrough
      @debounce = debounce.to_f
      @cache_entries = cache_entries
      @cache_bytes = cache_bytes
      @cache = {}
      @cache_size = 0
      @placed = nil
      @desired = nil
      @failed = nil
      @last_source = nil
      @pending_since = nil
    end

    # このフレームで出したい画像を伝える（毎フレーム呼ばれる）
    #
    # @param source [Object] ペイロードの同一性（パスと mtime など）。これが変わると
    #   別の画像として扱い、少し待ってから送る
    # @param payload [String, #call] 端末へ送るバイト列。Proc を渡すと、実際に送ると
    #   決まったときだけ呼ばれる（毎フレーム大きなファイルを読まないため）
    # @param row [Integer] 矩形の左上の行（1 始まりの端末座標）
    # @param col [Integer] 矩形の左上の桁（1 始まりの端末座標）
    # @param crop [Array(Integer, Integer, Integer, Integer), nil] 元画像から切り出す
    #   領域 [x, y, 幅, 高さ]（ズーム）。nil なら全体
    def request(source:, payload:, row:, col:, cols:, rows:,
                format: KittyGraphics::FORMAT_PNG, pixels: nil, crop: nil, now: monotonic)
      # 別のファイルに移ったときだけ待つ（最初の 1 枚と置き直しは待たせない）
      @pending_since = now if @last_source && @last_source != source
      @last_source = source
      @desired = Placement.new(source: source, key: [source, row, col, cols, rows, crop],
                               payload: payload, row: row, col: col, cols: cols, rows: rows,
                               format: format, pixels: pixels, crop: crop)
      true
    end

    # このフレームでは画像を出さない（置いてあれば flush で消える）。
    # 直前に頼まれた画像（デバウンスの基準）は忘れない。描画側は毎フレーム
    # clear してから request し直すため、ここで忘れると待ち時間が効かなくなる
    def clear
      @desired = nil
    end

    def placed?
      !@placed.nil?
    end

    # 変化があれば端末へ書く
    #
    # @param rewritten_rows [Array<Integer>, nil] このフレームで Renderer が書き換えた
    #   行（0 始まりの画面行）。画像の矩形と交差したら置き直す
    # @return [Boolean] 何か書いたか
    def flush(output, rewritten_rows: nil, now: monotonic)
      return false if output.nil?
      return false if @desired.nil? && @placed.nil?
      return remove(output) if @desired.nil?

      if @placed && @placed.key == @desired.key
        # 同じ画像・同じ位置。矩形の中が書き換えられたときだけ置き直す
        return false unless painted_over?(rewritten_rows)

        return send_image(output)
      end

      # 別のファイルへ移ったときは、古い画像を先に消してから待つ
      return remove(output) if @placed && @placed.source != @desired.source
      return false if waiting?(now)
      return false if @placed.nil? && @desired.key == @failed

      send_image(output)
    end

    # 置いてある画像をすべて消す（終了処理・全画面の再描画）
    def clear_all(output)
      @desired = nil
      @placed = nil
      @failed = nil
      @last_source = nil
      @pending_since = nil
      write(output, KittyGraphics.delete_all(passthrough: @passthrough))
    end

    private

    def monotonic
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def waiting?(now)
      return false if @pending_since.nil? || @debounce <= 0

      now - @pending_since < @debounce
    end

    # 画像の矩形（端末座標の 1 始まり）と、書き換えられた画面行（0 始まり）が重なるか
    def painted_over?(rewritten_rows)
      return false if rewritten_rows.nil? || rewritten_rows.empty?

      top = @placed.row - 1
      bottom = top + @placed.rows - 1
      rewritten_rows.any? { |row| row >= top && row <= bottom }
    end

    def remove(output)
      return false unless @placed

      @placed = nil
      write(output, KittyGraphics.delete(id: @id, passthrough: @passthrough))
    end

    def send_image(output)
      encoded = encoded_payload(@desired)
      if encoded.nil? || encoded.empty?
        # 読めなかった画像は覚えておき、毎フレーム読み直さない
        @failed = @desired.key
        return false
      end

      sequence = +''
      # 置き換えは先に消す（同じ ID を上書きしない端末があるため）
      sequence << KittyGraphics.delete(id: @id, passthrough: @passthrough) if @placed
      sequence << KittyGraphics.place_at(row: @desired.row, col: @desired.col,
                                        id: @id, payload: encoded, encoded: true,
                                        cols: @desired.cols, rows: @desired.rows,
                                        format: @desired.format, pixels: @desired.pixels,
                                        crop: @desired.crop, passthrough: @passthrough)
      return false unless write(output, sequence)

      @placed = @desired
      @failed = nil
      @pending_since = nil
      true
    end

    # Base64 済みのペイロードを返す。同じ画像は読み直さず、符号化もし直さない
    def encoded_payload(desired)
      key = desired.source
      cached = @cache[key]
      if cached
        # 直近に使ったものを残す（LRU）
        @cache.delete(key)
        @cache[key] = cached
        return cached
      end

      bytes = resolve(desired.payload)
      return nil if bytes.nil? || bytes.empty?

      encoded = [bytes].pack('m0')
      store(key, encoded)
      encoded
    end

    def store(key, encoded)
      # 1 枚で上限を超える画像は覚えない（キャッシュが丸ごと入れ替わるのを防ぐ）
      return if encoded.bytesize > @cache_bytes

      @cache[key] = encoded
      @cache_size += encoded.bytesize
      while @cache.size > @cache_entries || @cache_size > @cache_bytes
        oldest, value = @cache.first
        break if oldest.nil?

        @cache.delete(oldest)
        @cache_size -= value.bytesize
      end
    end

    # 送ると決まってから初めてバイト列を用意する
    def resolve(payload)
      payload.respond_to?(:call) ? payload.call : payload
    rescue StandardError
      nil
    end

    # 端末が閉じていても落ちない（画像はおまけの機能なので操作を止めない）
    def write(output, sequence)
      return false if output.nil? || sequence.nil? || sequence.empty?

      output.write(sequence)
      output.flush
      true
    rescue IOError, SystemCallError
      false
    end
  end
end
