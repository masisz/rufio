# frozen_string_literal: true

require_relative 'test_helper'
require 'minitest/autorun'
require 'stringio'
require_relative '../lib/rufio'

# 端末が Kitty グラフィックスに対応しているかの判定。
# 問い合わせ（a=q）と Primary DA（\e[c）を続けて送り、応答を読んで決める。
# 非対応端末でも DA は必ず返るので、待たされない。
class TestTerminalGraphics < Minitest::Test
  def setup
    Rufio::TerminalGraphics.reset!
  end

  def teardown
    Rufio::TerminalGraphics.reset!
  end

  def detect(response, env: {})
    output = StringIO.new
    Rufio::TerminalGraphics.detect!(input: StringIO.new(response), output: output,
                                   env: env, timeout: 0.05)
    output
  end

  # === 判定 ===

  def test_an_ok_answer_means_the_protocol_is_supported
    output = detect("\e_Gi=31;OK\e\\\e[?62;c")

    assert Rufio::TerminalGraphics.supported?
    assert_equal :kitty, Rufio::TerminalGraphics.protocol
    assert_includes output.string, 'a=q', '問い合わせを送ること'
    assert_includes output.string, "\e[c", 'Primary DA も送ること'
  end

  def test_a_device_answer_without_the_graphics_reply_means_unsupported
    detect("\e[?62;22;c")

    refute Rufio::TerminalGraphics.supported?
    assert_equal :none, Rufio::TerminalGraphics.protocol
  end

  def test_an_error_answer_means_unsupported
    detect("\e_Gi=31;ENOTSUPPORTED\e\\\e[?62;c")

    refute Rufio::TerminalGraphics.supported?
  end

  def test_no_answer_at_all_is_unsupported
    detect('')

    refute Rufio::TerminalGraphics.supported?
  end

  def test_the_answer_of_another_image_id_is_ignored
    detect("\e_Gi=99;OK\e\\\e[?62;c")

    refute Rufio::TerminalGraphics.supported?, '自分の問い合わせの応答だけを見ること'
  end

  # === 無効化 ===

  def test_the_environment_variable_turns_it_off
    output = detect("\e_Gi=31;OK\e\\", env: { 'RUFIO_IMAGE_PREVIEW' => '0' })

    refute Rufio::TerminalGraphics.supported?
    assert_empty output.string, '無効なら問い合わせも送らないこと'
  end

  def test_tmux_and_screen_are_off_by_default
    [{ 'TMUX' => '/tmp/tmux-1000/default,1,0' }, { 'STY' => '1234.pts-0' }].each do |env|
      Rufio::TerminalGraphics.reset!
      detect("\e_Gi=31;OK\e\\", env: env)
      refute Rufio::TerminalGraphics.supported?, env.keys.first
    end
  end

  # === セルのピクセル寸法 ===

  def test_the_cell_size_is_read_from_the_answer
    detect("\e_Gi=31;OK\e\\\e[6;32;15t\e[?62;c")

    assert_equal [15, 32], Rufio::TerminalGraphics.cell_pixels, 'CSI 16t の応答は [高さ, 幅] の順'
  end

  def test_an_unknown_cell_size_falls_back_to_a_default
    detect("\e_Gi=31;OK\e\\\e[?62;c")

    assert_equal Rufio::TerminalGraphics::DEFAULT_CELL_PIXELS, Rufio::TerminalGraphics.cell_pixels
  end

  def test_a_zero_cell_size_is_ignored
    detect("\e_Gi=31;OK\e\\\e[6;0;0t\e[?62;c")

    assert_equal Rufio::TerminalGraphics::DEFAULT_CELL_PIXELS, Rufio::TerminalGraphics.cell_pixels
  end

  # === 判定は 1 回だけ ===

  def test_the_result_is_remembered
    detect("\e_Gi=31;OK\e\\\e[?62;c")
    assert Rufio::TerminalGraphics.supported?

    # 2 回目は問い合わせを送らない
    output = StringIO.new
    Rufio::TerminalGraphics.detect!(input: StringIO.new(''), output: output, env: {}, timeout: 0.05)
    assert_empty output.string
    assert Rufio::TerminalGraphics.supported?
  end

  def test_detection_does_not_raise_on_a_closed_output
    output = StringIO.new
    output.close
    Rufio::TerminalGraphics.detect!(input: StringIO.new(''), output: output, env: {}, timeout: 0.05)

    refute Rufio::TerminalGraphics.supported?, '書けない端末でも落ちずに非対応にすること'
  end

  def test_huge_terminal_response_is_bounded
    flood = 'A' * (Rufio::TerminalGraphics::MAX_RESPONSE_BYTES * 4) + "\e_Gi=31;OK\e\\\e[?62;c"
    detect(flood)

    refute Rufio::TerminalGraphics.supported?, '応答サイズ上限を超えた後ろは読まないこと'
  end

  def test_out_of_range_cell_size_is_ignored
    detect("\e_Gi=31;OK\e\\\e[6;999999;999999t\e[?62;c")

    assert_equal Rufio::TerminalGraphics::DEFAULT_CELL_PIXELS, Rufio::TerminalGraphics.cell_pixels
    refute Rufio::TerminalGraphics.cell_pixels_known?, '異常なセル寸法は実測済みとして扱わないこと'
  end
end
