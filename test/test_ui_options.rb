# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "../lib/rufio"

# Phase 7: UI_OPTIONS config追加のテスト
# ConfigLoader.ui_options と UIRenderer への反映を検証
class TestUIOptions < Minitest::Test
  # === ConfigLoader.ui_options ===

  def test_ui_options_returns_hash
    opts = Rufio::ConfigLoader.ui_options
    assert_instance_of Hash, opts
  end

  def test_ui_options_has_panel_ratio
    opts = Rufio::ConfigLoader.ui_options
    assert opts.key?(:panel_ratio), "ui_optionsに :panel_ratio が含まれること"
  end

  def test_ui_options_has_preview_enabled
    opts = Rufio::ConfigLoader.ui_options
    assert opts.key?(:preview_enabled), "ui_optionsに :preview_enabled が含まれること"
  end

  def test_ui_options_panel_ratio_default_is_half
    opts = Rufio::ConfigLoader.ui_options
    assert_equal 0.5, opts[:panel_ratio], "デフォルトのpanel_ratioは0.5であること"
  end

  def test_ui_options_preview_enabled_default_is_true
    opts = Rufio::ConfigLoader.ui_options
    assert_equal true, opts[:preview_enabled], "デフォルトのpreview_enabledはtrueであること"
  end

  # === ConfigLoader.default_ui_options ===

  def test_default_ui_options_returns_hash
    opts = Rufio::ConfigLoader.default_ui_options
    assert_instance_of Hash, opts
  end

  def test_default_ui_options_panel_ratio
    assert_equal 0.5, Rufio::ConfigLoader.default_ui_options[:panel_ratio]
  end

  def test_default_ui_options_preview_enabled
    assert_equal true, Rufio::ConfigLoader.default_ui_options[:preview_enabled]
  end

  # === UIRenderer が ui_options を反映するか ===

  def test_ui_renderer_uses_panel_ratio_from_ui_options
    # デフォルトで0.5が使われること
    renderer = Rufio::UIRenderer.new(screen_width: 100, screen_height: 30)
    ratio = renderer.instance_variable_get(:@left_panel_ratio)
    assert_in_delta 0.5, ratio, 0.001, "UIRendererのleft_panel_ratioはui_options[:panel_ratio]を使うこと"
  end

  def test_ui_renderer_respects_explicit_panel_ratio
    # 明示的に指定した場合はそちらが優先されること
    renderer = Rufio::UIRenderer.new(screen_width: 100, screen_height: 30, left_panel_ratio: 0.3)
    ratio = renderer.instance_variable_get(:@left_panel_ratio)
    assert_in_delta 0.3, ratio, 0.001, "明示的に指定したleft_panel_ratioが使われること"
  end

  def test_ui_renderer_has_preview_enabled
    renderer = Rufio::UIRenderer.new(screen_width: 100, screen_height: 30)
    assert renderer.respond_to?(:preview_enabled?), "UIRendererにpreview_enabled?メソッドが存在すること"
  end

  def test_ui_renderer_preview_enabled_default_true
    renderer = Rufio::UIRenderer.new(screen_width: 100, screen_height: 30)
    assert renderer.preview_enabled?, "デフォルトではプレビューが有効であること"
  end

  def test_ui_renderer_preview_disabled_when_set
    renderer = Rufio::UIRenderer.new(screen_width: 100, screen_height: 30, preview_enabled: false)
    refute renderer.preview_enabled?, "preview_enabled: falseを指定した場合はプレビューが無効であること"
  end
end
