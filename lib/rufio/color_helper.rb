# frozen_string_literal: true

module Rufio
  class ColorHelper
    # 色変換結果のキャッシュ（毎フレームの計算を回避）
    # クラスインスタンス変数として初期化
    @color_to_ansi_cache = {}
    @color_to_selected_ansi_cache = {}
    @color_to_bg_ansi_cache = {}

    # キャッシュへのアクセサメソッド
    class << self
      attr_accessor :color_to_ansi_cache, :color_to_selected_ansi_cache, :color_to_bg_ansi_cache
    end

    # HSLからRGBへの変換
    def self.hsl_to_rgb(hue, saturation, lightness)
      h = hue.to_f / 360.0
      s = saturation.to_f / 100.0
      l = lightness.to_f / 100.0

      if s == 0
        # 彩度が0の場合（グレースケール）
        r = g = b = l
      else
        hue2rgb = lambda do |p, q, t|
          t += 1 if t < 0
          t -= 1 if t > 1
          return p + (q - p) * 6 * t if t < 1.0/6
          return q if t < 1.0/2
          return p + (q - p) * (2.0/3 - t) * 6 if t < 2.0/3
          p
        end

        q = l < 0.5 ? l * (1 + s) : l + s - l * s
        p = 2 * l - q

        r = hue2rgb.call(p, q, h + 1.0/3)
        g = hue2rgb.call(p, q, h)
        b = hue2rgb.call(p, q, h - 1.0/3)
      end

      [(r * 255).round, (g * 255).round, (b * 255).round]
    end

    # 色設定をANSIエスケープコードに変換（キャッシュ対応）
    def self.color_to_ansi(color_config)
      # キャッシュキーを生成（Hashの場合はハッシュ値を使用）
      cache_key = color_config.is_a?(Hash) ? color_config.hash : color_config

      # キャッシュチェック
      return @color_to_ansi_cache[cache_key] if @color_to_ansi_cache.key?(cache_key)

      # キャッシュミス時のみ計算
      result = case color_config
      when Hash
        if color_config[:hsl]
          # HSL形式: {hsl: [240, 100, 50]}
          hue, saturation, lightness = color_config[:hsl]
          r, g, b = hsl_to_rgb(hue, saturation, lightness)
          "\e[38;2;#{r};#{g};#{b}m"
        elsif color_config[:rgb]
          # RGB形式: {rgb: [100, 150, 200]}
          r, g, b = color_config[:rgb]
          "\e[38;2;#{r};#{g};#{b}m"
        elsif color_config[:hex]
          # HEX形式: {hex: "#ff0000"}
          hex = color_config[:hex].gsub('#', '')
          r = hex[0..1].to_i(16)
          g = hex[2..3].to_i(16)
          b = hex[4..5].to_i(16)
          "\e[38;2;#{r};#{g};#{b}m"
        else
          # デフォルト（白）
          "\e[37m"
        end
      when Symbol
        # 従来のシンボル形式をANSIコードに変換
        symbol_to_ansi(color_config)
      when String
        # 直接ANSIコードまたは名前が指定された場合
        if color_config.match?(/^\d+$/)
          "\e[#{color_config}m"
        else
          name_to_ansi(color_config)
        end
      when Integer
        # 数値が直接指定された場合
        "\e[#{color_config}m"
      else
        # デフォルト（白）
        "\e[37m"
      end

      # キャッシュに保存
      @color_to_ansi_cache[cache_key] = result
      result
    end

    # シンボルをANSIコードに変換
    def self.symbol_to_ansi(symbol)
      case symbol
      when :black then "\e[30m"
      when :red then "\e[31m"
      when :green then "\e[32m"
      when :yellow then "\e[33m"
      when :blue then "\e[34m"
      when :magenta then "\e[35m"
      when :cyan then "\e[36m"
      when :white then "\e[37m"
      when :bright_black then "\e[90m"
      when :bright_red then "\e[91m"
      when :bright_green then "\e[92m"
      when :bright_yellow then "\e[93m"
      when :bright_blue then "\e[94m"
      when :bright_magenta then "\e[95m"
      when :bright_cyan then "\e[96m"
      when :bright_white then "\e[97m"
      else "\e[37m" # デフォルト（白）
      end
    end

    # 色名をANSIコードに変換
    def self.name_to_ansi(name)
      symbol_to_ansi(name.to_sym)
    end

    # 背景色用のANSIコードを生成（キャッシュ対応）
    def self.color_to_bg_ansi(color_config)
      # キャッシュキーを生成
      cache_key = color_config.is_a?(Hash) ? color_config.hash : color_config

      # キャッシュチェック
      return @color_to_bg_ansi_cache[cache_key] if @color_to_bg_ansi_cache.key?(cache_key)

      # キャッシュミス時のみ計算
      ansi_code = color_to_ansi(color_config)
      # 前景色(38)を背景色(48)に変換
      result = ansi_code.gsub('38;', '48;')

      # キャッシュに保存
      @color_to_bg_ansi_cache[cache_key] = result
      result
    end

    # リセットコード
    def self.reset
      "\e[0m"
    end

    # ANSI escape codes を文字列から除去
    #
    # @param str [String] ANSI codes を含む文字列
    # @return [String] ANSI codes を除去した文字列
    def self.strip_ansi(str)
      return str if str.nil?
      str.gsub(/\e\[[0-9;]*m/, '')
    end

    # 選択状態（反転表示）用のANSIコードを生成（キャッシュ対応）
    def self.color_to_selected_ansi(color_config)
      # キャッシュキーを生成
      cache_key = color_config.is_a?(Hash) ? color_config.hash : color_config

      # キャッシュチェック
      return @color_to_selected_ansi_cache[cache_key] if @color_to_selected_ansi_cache.key?(cache_key)

      # キャッシュミス時のみ計算
      color_code = color_to_ansi(color_config)
      # 反転表示を追加
      result = color_code.gsub("\e[", "\e[7;").gsub("m", ";7m")

      # キャッシュに保存
      @color_to_selected_ansi_cache[cache_key] = result
      result
    end

    # プリセットHSLカラー
    def self.preset_hsl_colors
      {
        # ディレクトリ用の青系
        directory_blue: { hsl: [220, 80, 60] },
        directory_cyan: { hsl: [180, 70, 55] },
        
        # 実行ファイル用の緑系
        executable_green: { hsl: [120, 70, 50] },
        executable_lime: { hsl: [90, 80, 55] },
        
        # テキストファイル用
        text_white: { hsl: [0, 0, 90] },
        text_gray: { hsl: [0, 0, 70] },
        
        # 選択状態用
        selected_yellow: { hsl: [50, 90, 70] },
        selected_orange: { hsl: [30, 85, 65] },
        
        # プレビュー用
        preview_cyan: { hsl: [180, 60, 65] },
        preview_purple: { hsl: [270, 50, 70] }
      }
    end
  end
end