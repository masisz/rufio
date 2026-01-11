# frozen_string_literal: true

require_relative "test_helper"
require "minitest/autorun"
require "benchmark"

class TestColorHelper < Minitest::Test
  def setup
    # キャッシュをクリア
    Rufio::ColorHelper.instance_variable_set(:@color_to_ansi_cache, {})
    Rufio::ColorHelper.instance_variable_set(:@color_to_selected_ansi_cache, {})
    Rufio::ColorHelper.instance_variable_set(:@color_to_bg_ansi_cache, {})
  end

  # color_to_ansiメソッドのキャッシュが機能することを確認
  def test_color_to_ansi_cache_performance
    color_config = { hsl: [240, 100, 50] }

    # 1回目の呼び出し（キャッシュミス）
    first_time = Benchmark.realtime { Rufio::ColorHelper.color_to_ansi(color_config) }

    # 2回目の呼び出し（キャッシュヒット）
    second_time = Benchmark.realtime { Rufio::ColorHelper.color_to_ansi(color_config) }

    # キャッシュヒット時は計算コストがないため、1回目より速いはず
    assert second_time < first_time, "キャッシュが機能していません: 1回目=#{first_time}, 2回目=#{second_time}"
  end

  # color_to_bg_ansiメソッドがキャッシュを使用することを確認
  def test_color_to_bg_ansi_cache_performance
    color_config = { hsl: [240, 100, 50] }

    # 1回目の呼び出し（キャッシュミス）
    first_time = Benchmark.realtime { Rufio::ColorHelper.color_to_bg_ansi(color_config) }

    # 2回目の呼び出し（キャッシュヒット）
    second_time = Benchmark.realtime { Rufio::ColorHelper.color_to_bg_ansi(color_config) }

    # キャッシュヒット時は計算コストがないため、1回目より速いはず
    assert second_time < first_time, "color_to_bg_ansiのキャッシュが機能していません: 1回目=#{first_time}, 2回目=#{second_time}"
  end

  # 大量呼び出し時のパフォーマンステスト
  def test_bulk_call_performance
    color_configs = [
      { hsl: [240, 100, 50] },
      { hsl: [120, 80, 60] },
      { hsl: [0, 100, 50] },
      { rgb: [100, 150, 200] },
      { hex: "#ff0000" }
    ]

    iterations = 1000

    # キャッシュなしの時間を測定（毎回異なる色を使う）
    no_cache_time = Benchmark.realtime do
      iterations.times do |i|
        Rufio::ColorHelper.color_to_ansi({ hsl: [i % 360, 80, 60] })
      end
    end

    # キャッシュクリア
    Rufio::ColorHelper.instance_variable_set(:@color_to_ansi_cache, {})

    # キャッシュありの時間を測定（同じ色を繰り返し使う）
    cache_time = Benchmark.realtime do
      iterations.times do
        color_configs.each do |config|
          Rufio::ColorHelper.color_to_ansi(config)
        end
      end
    end

    # キャッシュが効いているので、キャッシュありの方が速いはず
    # （5色 × 1000回 = 5000回の呼び出しだが、実際の計算は5回だけ）
    puts "\nパフォーマンス比較:"
    puts "  キャッシュなし: #{(no_cache_time * 1000).round(2)}ms"
    puts "  キャッシュあり: #{(cache_time * 1000).round(2)}ms"
    puts "  改善率: #{((no_cache_time / cache_time).round(2))}x"
  end

  # color_to_bg_ansiの結果が正しいことを確認
  def test_color_to_bg_ansi_correctness
    color_config = { hsl: [240, 100, 50] }

    fg_code = Rufio::ColorHelper.color_to_ansi(color_config)
    bg_code = Rufio::ColorHelper.color_to_bg_ansi(color_config)

    # 前景色(38)が背景色(48)に変換されていることを確認
    assert bg_code.include?("48;2;"), "背景色コードが正しくありません: #{bg_code}"
    refute bg_code.include?("38;2;"), "前景色コードが残っています: #{bg_code}"
  end

  # color_to_bg_ansiがgsubを毎回実行しないことを確認
  def test_color_to_bg_ansi_does_not_call_gsub_repeatedly
    color_config = { hsl: [240, 100, 50] }

    # gsubの呼び出し回数をカウント
    gsub_call_count = 0
    String.class_eval do
      alias_method :original_gsub, :gsub
      define_method(:gsub) do |*args, &block|
        gsub_call_count += 1 if caller.any? { |line| line.include?('color_to_bg_ansi') }
        original_gsub(*args, &block)
      end
    end

    # 1回目の呼び出し
    Rufio::ColorHelper.color_to_bg_ansi(color_config)
    first_call_count = gsub_call_count

    # 2回目の呼び出し（キャッシュヒットすればgsubは呼ばれない）
    Rufio::ColorHelper.color_to_bg_ansi(color_config)
    second_call_count = gsub_call_count

    # 元に戻す
    String.class_eval do
      alias_method :gsub, :original_gsub
      remove_method :original_gsub
    end

    # 2回目の呼び出しでgsubが追加で呼ばれていないことを確認
    assert_equal first_call_count, second_call_count,
                 "color_to_bg_ansiのキャッシュが機能していません。gsub呼び出し回数: 1回目後=#{first_call_count}, 2回目後=#{second_call_count}"
  end

  # HSL→RGB変換が正しいことを確認
  def test_hsl_to_rgb_conversion
    # 赤 (0度, 100%, 50%)
    r, g, b = Rufio::ColorHelper.hsl_to_rgb(0, 100, 50)
    assert_equal 255, r
    assert_equal 0, g
    assert_equal 0, b

    # 青 (240度, 100%, 50%)
    r, g, b = Rufio::ColorHelper.hsl_to_rgb(240, 100, 50)
    assert_equal 0, r
    assert_equal 0, g
    assert_equal 255, b

    # グレー (0度, 0%, 50%)
    r, g, b = Rufio::ColorHelper.hsl_to_rgb(0, 0, 50)
    assert_equal 128, r
    assert_equal 128, g
    assert_equal 128, b
  end
end
