# frozen_string_literal: true

require 'rbconfig'
require_relative 'kitty_graphics'

module Rufio
  # 端末が画像表示（Kitty グラフィックスプロトコル）に対応しているかを 1 回だけ判定する。
  #
  # 判定は問い合わせ（`a=q`）＋ Primary DA（`\e[c`）を続けて送り、応答を読む方式。
  # 非対応の端末でも DA は返るため、無応答で待たされない。あわせて `CSI 16t` で
  # 1 セルのピクセル寸法も尋ねる（取れなければ既定値を使う）。
  #
  # 起動直後（raw モードにした後・メインループに入る前）に 1 回だけ呼ぶ。
  module TerminalGraphics
    # 問い合わせに使う画像 ID（他アプリの応答と混ざらないようにする）
    QUERY_ID = 31
    # 応答を待つ上限（秒）
    DEFAULT_TIMEOUT = 0.2
    # 端末応答の読み込み上限（異常な出力でのメモリ枯渇を防ぐ）
    MAX_RESPONSE_BYTES = 4096
    # セルのピクセル寸法が分からない端末での仮の値
    DEFAULT_CELL_PIXELS = [8, 16].freeze
    # 異常な端末応答で極端なセル寸法が入るのを防ぐ上限
    MAX_CELL_PIXELS = 1024
    # Primary DA の応答（これが来たら読み終わり）
    DA_PATTERN = /\e\[\?[0-9;]*c/.freeze
    # CSI 16t の応答: \e[6;<セルの高さ>;<セルの幅>t
    CELL_PATTERN = /\e\[6;(\d+);(\d+)t/.freeze

    @protocol = nil
    @cell_pixels = DEFAULT_CELL_PIXELS
    @cell_pixels_known = false

    class << self
      # @return [Symbol] :kitty / :none（未判定なら :none）
      def protocol
        @protocol || :none
      end

      def supported?
        protocol == :kitty
      end

      # @return [Array(Integer, Integer)] 1 セルの [幅, 高さ]（ピクセル）
      def cell_pixels
        @cell_pixels || DEFAULT_CELL_PIXELS
      end

      # 端末から実測したセル寸法か（既定値 8x16 の仮置きなら false）
      def cell_pixels_known?
        @cell_pixels_known == true
      end

      def detected?
        !@protocol.nil?
      end

      # 判定して結果を覚える。2 回目以降は何も送らない
      # @return [Symbol] protocol
      def detect!(input: $stdin, output: $stdout, env: ENV, timeout: DEFAULT_TIMEOUT)
        return protocol if detected?

        @protocol = :none
        @cell_pixels = DEFAULT_CELL_PIXELS
        @cell_pixels_known = false
        return @protocol unless enabled?(env)

        response = ask(input, output, timeout)
        return @protocol if response.nil?

        @protocol = KittyGraphics.ok?(response, id: QUERY_ID) ? :kitty : :none
        measured = parse_cell_pixels(response) || native_cell_pixels(output)
        if measured
          @cell_pixels = measured
          @cell_pixels_known = true
        end
        @protocol
      end

      # テストと再判定（端末が変わったとき）のために状態を捨てる
      def reset!
        @protocol = nil
        @cell_pixels = DEFAULT_CELL_PIXELS
        @cell_pixels_known = false
      end

      private

      # CSI 16t に応答しない端末では、ネイティブの TIOCGWINSZ からセル寸法を補う
      def native_cell_pixels(output)
        return nil unless output.respond_to?(:tty?) && output.tty?
        return nil unless defined?(NativeImage)

        NativeImage.cell_pixels
      rescue StandardError
        nil
      end

      # 設定より手前の足切り。Windows の端末と tmux / screen の中では既定で使わない
      def enabled?(env)
        return false if env['RUFIO_IMAGE_PREVIEW'] == '0'
        return false if windows?
        # tmux / screen は DCS パススルーの設定が必要なので、既定では無効（Phase 4 で設定化）
        return false if env['TMUX'] || env['STY']

        true
      end

      def windows?
        RbConfig::CONFIG['host_os'].to_s.match?(/mingw|mswin/)
      end

      # 問い合わせを送り、Primary DA の応答が来るか時間切れになるまで読む
      def ask(input, output, timeout)
        output.write(KittyGraphics.query(id: QUERY_ID))
        output.write("\e[16t")
        output.write("\e[c")
        output.flush
        read_response(input, timeout)
      rescue IOError, SystemCallError
        nil
      end

      def read_response(input, timeout)
        return '' if input.nil?

        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
        buffer = +''
        loop do
          remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
          break if remaining <= 0

          chunk = read_chunk(input, remaining)
          break if chunk.nil? || chunk.empty?

          buffer << chunk
          break if buffer.bytesize >= MAX_RESPONSE_BYTES || buffer.match?(DA_PATTERN)
        end
        buffer
      end

      def read_chunk(input, timeout)
        input.read_nonblock(1024)
      rescue IO::WaitReadable
        return nil unless input.respond_to?(:wait_readable) && input.wait_readable(timeout)

        begin
          input.read_nonblock(1024)
        rescue StandardError
          nil
        end
      rescue EOFError, IOError, SystemCallError, NoMethodError
        nil
      end

      def parse_cell_pixels(response)
        match = response.match(CELL_PATTERN)
        return nil unless match

        height = match[1].to_i
        width = match[2].to_i
        return nil unless width.between?(1, MAX_CELL_PIXELS) && height.between?(1, MAX_CELL_PIXELS)

        [width, height]
      end
    end
  end
end
