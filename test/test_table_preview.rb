# frozen_string_literal: true

require 'minitest/autorun'
require 'fileutils'
require 'tmpdir'
require_relative '../lib/rufio'

# 表プレビューの統合テスト
# FilePreview が 'table' を返すこと、UIRenderer がグリッドを描画すること、
# 表として読めない場合にテキストプレビューへ戻ること
class TestTablePreview < Minitest::Test
  CSV_CONTENT = <<~CSV
    name,price,stock
    apple,120,30
    みかん,150,8
    banana,80,12
  CSV

  # 表として読めない形式の代役
  class FailingTableSource < Rufio::TableSource
    class << self
      def supports?(path)
        File.extname(path.to_s) == '.boom'
      end

      def open(_path, limits: nil, options: {})
        raise Rufio::TableSource::ParseError, 'test failure'
      end
    end
  end

  def setup
    @test_dir = Dir.mktmpdir('rufio_table_preview_test')
    @csv_path = File.join(@test_dir, 'sales.csv')
    File.write(@csv_path, CSV_CONTENT)
    File.write(File.join(@test_dir, 'notes.txt'), "plain text\nsecond line\n")

    @file_preview = Rufio::FilePreview.new
  end

  def teardown
    Rufio::PreviewRegistry.reset!
    FileUtils.rm_rf(@test_dir) if @test_dir && Dir.exist?(@test_dir)
  end

  def strip_ansi(str)
    str.to_s.gsub(/\e\[[0-9;]*m/, '')
  end

  # === FilePreview ===

  def test_csv_is_previewed_as_table
    preview = @file_preview.preview_file(@csv_path)

    assert_equal 'table', preview[:type]
    assert_instance_of Rufio::TableDocument, preview[:document]
    assert_equal %w[name price stock], preview[:document].sheet.header
    assert_equal 3, preview[:document].sheet.row_count
  end

  def test_table_preview_provides_plain_lines_for_other_consumers
    preview = @file_preview.preview_file(@csv_path)

    assert(preview[:lines].any? { |line| line.include?('A name') })
    assert(preview[:lines].any? { |line| line.include?('apple') })
  end

  def test_text_file_is_not_a_table
    preview = @file_preview.preview_file(File.join(@test_dir, 'notes.txt'))

    assert_equal 'text', preview[:type]
    assert_nil preview[:document]
  end

  def test_cp932_csv_is_decoded_instead_of_mojibake
    path = File.join(@test_dir, 'cp932.csv')
    File.binwrite(path, "商品,単価\nみかん,150\n".encode('CP932').b)
    preview = @file_preview.preview_file(path)

    assert_equal 'table', preview[:type]
    assert_equal 'CP932', preview[:encoding]
    assert_equal %w[商品 単価], preview[:document].sheet.header
  end

  def test_utf16_csv_is_not_treated_as_binary
    path = File.join(@test_dir, 'utf16.csv')
    File.binwrite(path, "\xFF\xFE".b + "name,price\r\napple,120\r\n".encode('UTF-16LE').b)
    preview = @file_preview.preview_file(path)

    assert_equal 'table', preview[:type], 'NUL バイトの多い UTF-16 でも表として扱うこと'
    assert_equal %w[name price], preview[:document].sheet.header
  end

  def test_empty_csv_is_still_handled
    path = File.join(@test_dir, 'empty.csv')
    File.write(path, '')
    preview = @file_preview.preview_file(path)

    assert_equal 'empty', preview[:type], '0 バイトは従来どおり empty'
  end

  def test_header_only_csv
    path = File.join(@test_dir, 'header_only.csv')
    File.write(path, "a,b\n")
    preview = @file_preview.preview_file(path)

    assert_equal 'table', preview[:type]
    assert_equal %w[a b], preview[:document].sheet.header
    assert_equal 0, preview[:document].sheet.row_count
    assert preview[:document].sheet.empty?
  end

  def test_unparsable_table_falls_back_to_text_preview
    Rufio::PreviewRegistry.register_table_source(FailingTableSource)
    path = File.join(@test_dir, 'broken.boom')
    File.write(path, "line one\nline two\n")

    preview = @file_preview.preview_file(path)

    refute_equal 'table', preview[:type]
    assert_equal 'test failure', preview[:table_error]
    assert_includes preview[:lines].first, 'not parsed as table'
    assert_includes preview[:lines], 'line one'
  end

  # === PreviewRegistry ===

  def test_registry_finds_the_csv_source
    assert_equal Rufio::CsvTableSource, Rufio::PreviewRegistry.table_source_for('a.csv')
    assert_nil Rufio::PreviewRegistry.table_source_for('a.txt')
    assert_nil Rufio::PreviewRegistry.table_source_for(nil)
  end

  def test_registered_source_takes_precedence
    Rufio::PreviewRegistry.register_table_source(FailingTableSource)
    assert_equal FailingTableSource, Rufio::PreviewRegistry.table_source_for('a.boom')
    assert Rufio::PreviewRegistry.table?('a.boom')
  end

  def test_reset_restores_the_defaults
    Rufio::PreviewRegistry.register_table_source(FailingTableSource)
    Rufio::PreviewRegistry.reset!
    assert_nil Rufio::PreviewRegistry.table_source_for('a.boom')
  end

  # === UIRenderer ===

  def renderer_for(width: 100, height: 24)
    screen = Rufio::Screen.new(width, height)
    listing = Rufio::DirectoryListing.new(@test_dir)
    handler = Rufio::KeybindHandler.new
    handler.set_directory_listing(listing)

    ui = Rufio::UIRenderer.new(
      screen_width: width, screen_height: height,
      keybind_handler: handler, directory_listing: listing,
      file_preview: Rufio::FilePreview.new
    )

    entries = listing.list_entries
    index = entries.index { |entry| entry[:name] == 'sales.csv' }
    refute_nil index, 'sales.csv がエントリに含まれること'
    handler.select_index(index)

    [screen, ui, handler]
  end

  def screen_text(screen, height)
    (0...height).map { |y| strip_ansi(screen.row(y)) }.join("\n")
  end

  def test_split_pane_draws_the_grid
    screen, ui, = renderer_for
    ui.draw_screen(screen)
    text = screen_text(screen, 24)

    assert_includes text, 'A name'
    assert_includes text, 'apple'
    assert_includes text, 'みかん'
    assert_includes text, '3 rows  3 cols'
  end

  def test_fullscreen_preview_draws_the_grid
    screen, ui, handler = renderer_for
    assert handler.focus_preview_pane
    ui.draw_screen(screen)
    text = screen_text(screen, 24)

    assert_includes text, '[PREVIEW MODE]'
    assert_includes text, 'A name'
    assert_includes text, 'banana'
  end

  def test_grid_rows_are_numbered
    screen, ui, handler = renderer_for
    handler.focus_preview_pane
    ui.draw_screen(screen)
    rows = (0...24).map { |y| strip_ansi(screen.row(y)) }

    apple_row = rows.find { |row| row.include?('apple') }
    assert_match(/\A\s*1 \|/, apple_row)
  end

  def test_scrolling_moves_the_data_rows
    screen, ui, handler = renderer_for
    handler.focus_preview_pane
    ui.draw_screen(screen)
    assert_includes screen_text(screen, 24), 'apple'

    handler.scroll_preview_down
    screen.clear
    ui.draw_screen(screen)
    text = screen_text(screen, 24)

    refute_includes text, 'apple', '1 行スクロールしたら先頭行が消えること'
    assert_includes text, 'みかん'
    assert_includes text, 'A name', 'ヘッダ行は固定されたままであること'
  end

  def test_narrow_pane_reports_hidden_columns
    screen, ui, = renderer_for(width: 60)
    ui.draw_screen(screen)
    text = screen_text(screen, 24)

    assert_includes text, '+1 hidden', '収まらない列数を最下行に出すこと'
  end
end
