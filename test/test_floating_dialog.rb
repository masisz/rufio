#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'test_helper'

class TestFloatingDialog < Minitest::Test
  def setup
    @dialog_renderer = Rufio::DialogRenderer.new
    @keybind_handler = Rufio::KeybindHandler.new
  end

  def test_display_width_calculation
    # ASCII文字のテスト
    assert_equal 5, Rufio::TextUtils.display_width("Hello")

    # 日本語文字のテスト（全角文字は幅2として計算）
    assert_equal 10, Rufio::TextUtils.display_width("こんにちは")  # 5文字 × 2 = 10

    # 混在文字列のテスト
    assert_equal 9, Rufio::TextUtils.display_width("Hello世界")  # 5 + 2*2 = 9
  end

  def test_calculate_center_calculation
    x, y = @dialog_renderer.calculate_center(40, 8)

    # 中央位置が正の値であることを確認
    assert x > 0, "X position should be positive"
    assert y > 0, "Y position should be positive"

    # 最小値が1であることを確認
    assert x >= 1, "X position should be at least 1"
    assert y >= 1, "Y position should be at least 1"
  end

  def test_floating_dialog_methods_exist
    # 必要なメソッドが定義されていることを確認
    assert_respond_to @dialog_renderer, :draw_floating_window, "draw_floating_window method should exist"
    assert_respond_to @dialog_renderer, :clear_area, "clear_area method should exist"
    assert_respond_to @dialog_renderer, :calculate_center, "calculate_center method should exist"
    assert_respond_to @dialog_renderer, :calculate_dimensions, "calculate_dimensions method should exist"
  end

  def test_show_deletion_result_with_success
    # 成功時のメソッド呼び出しテスト（実際の画面出力はしない）
    # モック化して副作用をテスト
    result = nil
    @dialog_renderer.stub :draw_floating_window, nil do
      @dialog_renderer.stub :clear_area, nil do
        # STDINをモック化
        STDIN.stub :getch, 'y' do
          # メソッドが正常に呼び出せることを確認（例外が発生しないことを確認）
          begin
            @keybind_handler.send(:show_deletion_result, 3, 3, [])
            result = true
          rescue StandardError
            result = false
          end
        end
      end
    end
    assert result, "show_deletion_result should not raise an exception"
  end

  def test_show_deletion_result_with_errors
    error_messages = ["file1.txt: Permission denied", "file2.txt: File not found"]

    # エラー付きの結果表示テスト
    result = nil
    @dialog_renderer.stub :draw_floating_window, nil do
      @dialog_renderer.stub :clear_area, nil do
        STDIN.stub :getch, 'n' do
          begin
            @keybind_handler.send(:show_deletion_result, 1, 3, error_messages)
            result = true
          rescue StandardError
            result = false
          end
        end
      end
    end
    assert result, "show_deletion_result should not raise an exception"
  end
end

# テスト実行
if __FILE__ == $0
  puts "=== Floating Dialog Tests ==="
  Minitest.run([])
  puts "=== Tests Completed ==="
end