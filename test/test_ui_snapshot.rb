# frozen_string_literal: true

require "minitest/autorun"
require "fileutils"
require_relative "ui_test_harness"

# スナップショットテスト（方式1）
# 画面出力をファイルに保存し、将来の出力と比較してリグレッションを検出
#
# 使い方:
#   通常実行: ruby test/test_ui_snapshot.rb
#   スナップショット更新: UPDATE_SNAPSHOTS=1 ruby test/test_ui_snapshot.rb
#
class TestUISnapshot < Minitest::Test
  SNAPSHOT_DIR = File.join(__dir__, "snapshots")

  def setup
    @harness = Rufio::UITestHarness.new(width: 80, height: 24)
    @harness.setup_terminal_ui
    FileUtils.mkdir_p(SNAPSHOT_DIR)
  end

  def teardown
    @harness.cleanup
  end

  # === メイン画面のスナップショットテスト ===

  def test_main_screen_layout
    @harness.render_frame
    assert_snapshot("main_screen", @harness.screen_text)
  end

  def test_header_display
    @harness.render_frame
    header_line = @harness.line(23)  # ヘッダは最下行（y=h-1）

    # ヘッダーに"rufio"が含まれることを確認
    assert_match(/rufio/, header_line, "Header should contain 'rufio'")

    # スナップショット
    assert_snapshot("header_line", header_line)
  end

  def test_mode_tabs_display
    @harness.render_frame
    tab_line = @harness.line(23)  # モードタブ+パス+バージョン統合行（y=h-1）

    # タブに"Files"が含まれることを確認
    assert_match(/Files/, tab_line, "Tab line should contain 'Files'")

    assert_snapshot("mode_tabs", tab_line)
  end

  def test_footer_display
    @harness.render_frame
    footer_line = @harness.line(0)  # フッタは最上行（y=0）

    # スナップショット（?:helpは削除済み）
    assert_snapshot("footer_line", footer_line)
  end

  # === ナビゲーション後のスナップショットテスト ===

  def test_after_navigation_down
    @harness.render_frame
    @harness.send_keys("j", "j")  # 2行下に移動

    assert_snapshot("after_nav_down", @harness.screen_text)
  end

  def test_after_navigation_to_bottom
    @harness.render_frame
    @harness.send_keys("G")  # 最下部に移動

    assert_snapshot("after_nav_bottom", @harness.screen_text)
  end

  def test_after_navigation_to_top
    @harness.render_frame
    @harness.send_keys("G", "g")  # 最下部→最上部

    assert_snapshot("after_nav_top", @harness.screen_text)
  end

  # === ディレクトリリストのスナップショットテスト ===

  def test_directory_list_content
    @harness.render_frame

    # ディレクトリリスト領域（行1〜21）を取得（フッタ1行分移動）
    dir_list_lines = (1..20).map { |y| @harness.line(y) }.join("\n")

    assert_snapshot("directory_list", dir_list_lines)
  end

  def test_file_preview_area
    @harness.render_frame

    # ファイルにカーソルを合わせる（サブディレクトリをスキップ）
    5.times { @harness.send_keys("j") }

    # プレビュー領域を取得（右側40カラム）
    preview_lines = (1..9).map do |y|
      line = @harness.line(y)
      line[40..-1] || ""
    end.join("\n")

    assert_snapshot("file_preview", preview_lines)
  end

  # === 特殊状態のスナップショットテスト ===

  def test_empty_directory
    # 空のディレクトリをテスト（..のみ表示）
    empty_dir = Dir.mktmpdir("rufio_empty_test")

    begin
      harness = Rufio::UITestHarness.new(width: 80, height: 24)
      harness.instance_variable_set(:@test_dir, empty_dir)
      harness.setup_terminal_ui
      harness.render_frame

      assert_snapshot("empty_directory", harness.screen_text)
    ensure
      harness.cleanup if harness
      FileUtils.rm_rf(empty_dir)
    end
  end

  # === 画面サイズ変更のスナップショットテスト ===

  def test_narrow_screen
    narrow_harness = Rufio::UITestHarness.new(width: 40, height: 24)
    narrow_harness.setup_terminal_ui

    begin
      narrow_harness.render_frame
      assert_snapshot("narrow_screen", narrow_harness.screen_text)
    ensure
      narrow_harness.cleanup
    end
  end

  def test_short_screen
    short_harness = Rufio::UITestHarness.new(width: 80, height: 10)
    short_harness.setup_terminal_ui

    begin
      short_harness.render_frame
      assert_snapshot("short_screen", short_harness.screen_text)
    ensure
      short_harness.cleanup
    end
  end

  private

  # スナップショットアサーション
  # UPDATE_SNAPSHOTS=1 で実行するとスナップショットを更新
  def assert_snapshot(name, actual)
    path = File.join(SNAPSHOT_DIR, "#{name}.txt")

    # 動的な値を正規化（一時ディレクトリパスなど）
    normalized_actual = normalize_dynamic_values(actual)

    if ENV["UPDATE_SNAPSHOTS"]
      File.write(path, normalized_actual)
      puts "\n  [UPDATED] Snapshot: #{name}"
      pass  # スナップショット更新時はパス
    elsif File.exist?(path)
      expected = File.read(path)

      if expected != normalized_actual
        # 差分を出力
        diff_path = File.join(SNAPSHOT_DIR, "#{name}.diff.txt")
        File.write(diff_path, "=== EXPECTED ===\n#{expected}\n\n=== ACTUAL ===\n#{normalized_actual}")

        assert_equal expected, normalized_actual,
          "Snapshot mismatch: #{name}\nSee #{diff_path} for details.\n" \
          "Run with UPDATE_SNAPSHOTS=1 to update."
      else
        pass
      end
    else
      # スナップショットが存在しない場合は作成
      File.write(path, normalized_actual)
      puts "\n  [CREATED] New snapshot: #{name}"
      pass
    end
  end

  # 動的な値を正規化（一時ディレクトリパスなど）
  def normalize_dynamic_values(text)
    result = text
      # macOS tmpdir パス（完全形・切り詰め形を両方処理）
      # 完全形: /var/folders/xx/xxxx/T/rufio_ui_test12345-456-abc
      # 切り詰め形（モードタブ内）: /var/folders/kl/fq_4fzdx3cb3h
      .gsub(%r{/var/folders/[^\s"]+}, "/tmp/TEST_DIR")
      # Linux tmpdir パス（完全形・切り詰め形を両方処理）
      # 完全形: /tmp/rufio_ui_test20260223-1234-abc123
      # 切り詰め形: /tmp/rufio_ui_te
      .gsub(%r{/tmp/rufio_[^\s"]+}, "/tmp/TEST_DIR")
      # Linux generic tmpdir: /tmp/d20260223-1234-xyz
      .gsub(%r{/tmp/d\d+-\d+-[^\s"]+}, "/tmp/TEST_DIR")
      # 残余の "..." 短縮パスパターン
      .gsub(%r{\.\.\.[^"\n]*TEST_DIR}, "...TEST_DIR")
      .gsub(%r{test\d+-\d+-\w+}, "TEST_DIR")
      # バージョン番号を正規化（リリースごとに変わるため）
      # 例: "rufio v0.80.0" → "rufio vX.X.X"
      .gsub(/rufio v\d+\.\d+\.\d+/, "rufio vX.X.X")
      # ディレクトリサイズを正規化（ファイルシステム依存を回避）
      # 先頭スペース込みでマッチし、元の文字数を保ったまま SIZE に置き換える（長さ保存）
      # 例: "  4.0K" (6文字) → "  SIZE" (6文字), "   32B" (6文字) → "  SIZE" (6文字)
      .gsub(/ *\d+\.?\d*[BKMG](?=\s*\|)/) { |m| "SIZE".rjust(m.length) }

    # 各行の末尾スペースをトリム
    # パス正規化後に行長が変わるためプラットフォーム間の差異を吸収する
    result.lines.map(&:rstrip).join("\n")
  end
end
