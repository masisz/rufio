# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/rufio/screen'
require_relative '../lib/rufio/text_utils'
require_relative '../lib/rufio/color_helper'

module Rufio
  class TestScreenOverlay < Minitest::Test
    def setup
      @screen = Screen.new(20, 10)
    end

    def test_overlay_initially_disabled
      refute @screen.overlay_enabled?
    end

    def test_enable_overlay
      @screen.enable_overlay
      assert @screen.overlay_enabled?
    end

    def test_disable_overlay
      @screen.enable_overlay
      @screen.disable_overlay
      refute @screen.overlay_enabled?
    end

    def test_put_overlay_without_enabling
      # オーバーレイが無効な場合は何も起こらない
      @screen.put_overlay(0, 0, 'X')
      # ベースレイヤーには影響しない
      assert_equal ' ', @screen.get_cell(0, 0)[:char]
    end

    def test_put_overlay_overwrites_base
      # ベースレイヤーに描画
      @screen.put(0, 0, 'A')
      assert_equal 'A', @screen.get_cell(0, 0)[:char]

      # オーバーレイを有効化して描画
      @screen.enable_overlay
      @screen.put_overlay(0, 0, 'X')

      # row()の結果にはオーバーレイが反映される
      row = @screen.row(0)
      assert_includes row, 'X'
      refute_includes row, 'A'
    end

    def test_overlay_partial_coverage
      # ベースレイヤーに描画
      @screen.put_string(0, 0, 'ABCDE')

      # オーバーレイを有効化して一部だけ上書き
      @screen.enable_overlay
      @screen.put_overlay(2, 0, 'X')

      row = @screen.row(0)
      # A, B はベースから、X はオーバーレイから、D, E はベースから
      assert_includes row, 'A'
      assert_includes row, 'B'
      assert_includes row, 'X'
      assert_includes row, 'D'
      assert_includes row, 'E'
    end

    def test_clear_overlay
      @screen.put_string(0, 0, 'BASE')
      @screen.enable_overlay
      @screen.put_overlay_string(0, 0, 'OVER')

      # オーバーレイをクリア
      @screen.clear_overlay

      # ベースレイヤーが見えるようになる
      row = @screen.row(0)
      assert_includes row, 'B'
      assert_includes row, 'A'
      assert_includes row, 'S'
      assert_includes row, 'E'
    end

    def test_disable_overlay_marks_dirty
      @screen.enable_overlay
      @screen.put_overlay(0, 0, 'X')
      @screen.clear_dirty  # dirtyをクリア

      @screen.disable_overlay

      # オーバーレイが描画されていた行がdirtyになる
      assert_includes @screen.dirty_rows, 0
    end

    def test_put_overlay_string
      @screen.enable_overlay
      @screen.put_overlay_string(0, 0, 'Hello')

      row = @screen.row(0)
      assert_includes row, 'H'
      assert_includes row, 'e'
      assert_includes row, 'l'
      assert_includes row, 'o'
    end

    def test_overlay_with_color
      @screen.enable_overlay
      @screen.put_overlay(0, 0, 'X', fg: "\e[31m")

      row = @screen.row(0)
      # 赤色のANSIコードが含まれる
      assert_includes row, "\e[31m"
      assert_includes row, 'X'
    end

    def test_fullwidth_character_in_overlay
      @screen.enable_overlay
      @screen.put_overlay(0, 0, '日', width: 2)

      row = @screen.row(0)
      assert_includes row, '日'
    end
  end
end
