# frozen_string_literal: true

require 'minitest/autorun'

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'rufio'

# オーバーレイ上の複数ダイアログ描画時のテスト
# コマンドモードプロンプト（幅50）→ 補完候補ウィンドウ（幅40）の
# 連続描画で旧ウィンドウの縦線が残らないことを検証
class TestOverlayClearing < Minitest::Test
  def setup
    @screen = Rufio::Screen.new(80, 24)
    @dialog_renderer = Rufio::DialogRenderer.new
  end

  # クリアせずに描画すると旧ボーダーが残る（バグの再現）
  def test_without_clear_old_borders_remain
    @screen.enable_overlay

    # 1. コマンドモードプロンプトを描画（幅50、右端 x=64）
    @dialog_renderer.draw_floating_window_to_overlay(
      @screen, 15, 8, 50, 8,
      "Command Mode", ["", "rake:_", "", "Tab: Complete"],
      { border_color: "\e[34m", title_color: "\e[1;34m", content_color: "\e[37m" }
    )

    # 2. クリアせずに補完ウィンドウを描画（幅40、右端 x=59）
    @dialog_renderer.draw_floating_window_to_overlay(
      @screen, 20, 7, 40, 10,
      "Completions (3)", ["", "  rake:test", "  rake:build", "  rake:clean", "", "Press any key..."],
      { border_color: "\e[33m", title_color: "\e[1;33m", content_color: "\e[37m" }
    )

    # 旧プロンプトの右ボーダー（x=64）が残っている
    cell = @screen.instance_variable_get(:@overlay_cells)[11][64]
    refute_nil cell, "クリアしなければ旧ボーダーが残るはず"
    assert_equal '│', cell[:char]
  end

  # クリアしてから描画すると旧ボーダーが消える（修正後の動作）
  def test_with_clear_old_borders_are_removed
    @screen.enable_overlay

    # 1. コマンドモードプロンプトを描画（幅50）
    @dialog_renderer.draw_floating_window_to_overlay(
      @screen, 15, 8, 50, 8,
      "Command Mode", ["", "rake:_", "", "Tab: Complete"],
      { border_color: "\e[34m", title_color: "\e[1;34m", content_color: "\e[37m" }
    )

    # 2. クリアしてから補完ウィンドウを描画
    @screen.clear_overlay

    @dialog_renderer.draw_floating_window_to_overlay(
      @screen, 20, 7, 40, 10,
      "Completions (3)", ["", "  rake:test", "  rake:build", "  rake:clean", "", "Press any key..."],
      { border_color: "\e[33m", title_color: "\e[1;33m", content_color: "\e[37m" }
    )

    # 旧プロンプトの右ボーダー（x=64）が消えている
    cell = @screen.instance_variable_get(:@overlay_cells)[11][64]
    assert_nil cell, "クリア後に旧ボーダーが残っていてはならない"

    # 新ウィンドウのボーダーは正しく存在する
    overlay = @screen.instance_variable_get(:@overlay_cells)
    left_border = overlay[10][20]
    right_border = overlay[10][59]
    refute_nil left_border, "新ウィンドウの左ボーダーが存在するべき"
    refute_nil right_border, "新ウィンドウの右ボーダーが存在するべき"
    assert_equal '│', left_border[:char]
    assert_equal '│', right_border[:char]
  end
end
