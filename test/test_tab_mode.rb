# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/rufio/tab_mode_manager'

module Rufio
  class TestTabModeManager < Minitest::Test
    def setup
      @manager = TabModeManager.new
    end

    # モード一覧のテスト
    def test_available_modes
      modes = @manager.available_modes
      assert_equal %i[files logs jobs help], modes
    end

    def test_default_mode_is_files
      assert_equal :files, @manager.current_mode
    end

    # Tabキーでの切り替えテスト
    def test_next_mode_cycles_through_modes
      initial_mode = @manager.current_mode
      assert_equal :files, initial_mode

      @manager.next_mode
      assert_equal :logs, @manager.current_mode

      @manager.next_mode
      assert_equal :jobs, @manager.current_mode

      @manager.next_mode
      assert_equal :help, @manager.current_mode

      @manager.next_mode
      assert_equal :files, @manager.current_mode
    end

    def test_previous_mode_cycles_backwards
      assert_equal :files, @manager.current_mode

      @manager.previous_mode
      assert_equal :help, @manager.current_mode

      @manager.previous_mode
      assert_equal :jobs, @manager.current_mode
    end

    # 特定モードへの切り替え
    def test_switch_to_specific_mode
      @manager.switch_to(:help)
      assert_equal :help, @manager.current_mode

      @manager.switch_to(:jobs)
      assert_equal :jobs, @manager.current_mode
    end

    def test_switch_to_invalid_mode_does_nothing
      @manager.switch_to(:invalid_mode)
      assert_equal :files, @manager.current_mode
    end

    # 表示用テキストのテスト
    def test_mode_labels
      labels = @manager.mode_labels
      assert_equal 'Files', labels[:files]
      assert_equal 'Help', labels[:help]
      assert_equal 'Logs', labels[:logs]
      assert_equal 'Jobs', labels[:jobs]
    end

    # モードタブの表示テキスト生成テスト
    def test_render_tab_line
      @manager.switch_to(:files)
      tab_line = @manager.render_tab_line(80)

      # 現在のモードがハイライトされていることを確認
      assert_includes tab_line, 'Files'
      assert_includes tab_line, 'Help'
      assert_includes tab_line, 'Logs'
      assert_includes tab_line, 'Jobs'
    end

    def test_render_tab_line_highlights_current_mode
      @manager.switch_to(:help)
      tab_line = @manager.render_tab_line(80)

      # Helpがハイライトされていることを確認
      # シアン背景(\e[46m) + 黒文字(\e[30m) + 太字(\e[1m)で表現される
      assert_match(/\e\[46m\e\[30m\e\[1m\s*Help\s*\e\[0m/, tab_line)
    end

    # モード情報の取得
    def test_current_mode_info
      @manager.switch_to(:logs)
      info = @manager.current_mode_info

      assert_equal :logs, info[:mode]
      assert_equal 'Logs', info[:label]
      assert_equal 1, info[:index]  # files=0, logs=1, jobs=2, help=3
    end

    # 状態コールバックのテスト
    def test_on_mode_change_callback
      changed_to = nil
      @manager.on_mode_change { |mode| changed_to = mode }

      @manager.switch_to(:help)
      assert_equal :help, changed_to
    end
  end
end
