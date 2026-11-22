# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/rufio'

# TableLayout: 列幅算出（全角混在）、可視列、狭い幅でのフォールバック
class TestTableLayout < Minitest::Test
  def sheet(rows:, header: nil, name: 'test.csv', row_truncated: false, column_truncated: false)
    Rufio::MemoryTableSheet.new(
      rows: rows, header: header, name: name,
      row_truncated: row_truncated, column_truncated: column_truncated
    )
  end

  def wide_sheet
    sheet(header: %w[name price stock], rows: [%w[apple 120 30], %w[みかん 150 8]])
  end

  # === 列幅 ===

  def test_column_width_uses_longest_value
    layout = Rufio::TableLayout.build(sheet(header: %w[a], rows: [['abcdefgh']]), 80)
    assert_equal 8, layout.column_width(0)
  end

  def test_column_width_counts_fullwidth_as_two
    layout = Rufio::TableLayout.build(sheet(header: %w[a], rows: [['みかん']]), 80)
    assert_equal 6, layout.column_width(0), '全角 3 文字は幅 6'
  end

  def test_column_width_includes_header_title
    # 見出しは "A name" のように列ラベル付きで表示されるため幅 6 以上になる
    layout = Rufio::TableLayout.build(sheet(header: %w[name], rows: [['a']]), 80)
    assert_equal 6, layout.column_width(0)
  end

  def test_column_width_has_minimum
    layout = Rufio::TableLayout.build(sheet(rows: [['a']]), 80)
    assert_equal Rufio::TableLayout::MIN_COLUMN_WIDTH, layout.column_width(0)
  end

  def test_column_width_is_capped
    layout = Rufio::TableLayout.build(sheet(rows: [['x' * 100]]), 200, max_column_width: 10)
    assert_equal 10, layout.column_width(0)
  end

  def test_cells_are_padded_to_the_column_width
    layout = Rufio::TableLayout.build(wide_sheet, 80)
    cell = layout.format_cell('apple', 0)
    assert_equal layout.column_width(0), Rufio::TextUtils.display_width(cell)
  end

  def test_fullwidth_cells_keep_the_grid_aligned
    layout = Rufio::TableLayout.build(wide_sheet, 80)
    ascii = layout.row_line(1, %w[apple 120 30])
    japanese = layout.row_line(2, %w[みかん 150 8])

    assert_equal Rufio::TextUtils.display_width(ascii), Rufio::TextUtils.display_width(japanese)
    # 区切りで分けた各区画の表示幅が一致すれば、全角が混ざっても桁が揃っている
    widths = ->(line) { line.split('|').map { |part| Rufio::TextUtils.display_width(part) } }
    assert_equal widths.call(ascii), widths.call(japanese), '各区画の表示幅が揃うこと'
  end

  def test_newlines_and_tabs_are_collapsed_for_display
    layout = Rufio::TableLayout.build(sheet(rows: [["two\nlines"]]), 80)
    assert_includes layout.row_line(1, ["two\nlines"]), 'two lines'
    refute_includes layout.row_line(1, ["two\nlines"]), "\n"
  end

  # === 行・ヘッダ ===

  def test_header_line_shows_column_labels_and_titles
    line = Rufio::TableLayout.build(wide_sheet, 80).header_line
    assert_includes line, 'A name'
    assert_includes line, 'B price'
    assert_includes line, 'C stock'
  end

  def test_header_line_shows_only_labels_without_header_row
    line = Rufio::TableLayout.build(sheet(rows: [%w[1 2]]), 80).header_line
    assert_includes line, 'A'
    assert_includes line, 'B'
  end

  def test_row_line_shows_row_number
    line = Rufio::TableLayout.build(wide_sheet, 80).row_line(7, %w[apple 120 30])
    assert_match(/\A\s*7 \|/, line)
  end

  def test_lines_are_exactly_the_requested_width
    layout = Rufio::TableLayout.build(wide_sheet, 40)
    assert_equal 40, Rufio::TextUtils.display_width(layout.header_line)
    assert_equal 40, Rufio::TextUtils.display_width(layout.row_line(1, %w[apple 120 30]))
    assert_equal 40, Rufio::TextUtils.display_width(layout.row_line(1, nil))
  end

  def test_missing_cells_render_as_blanks
    layout = Rufio::TableLayout.build(wide_sheet, 60)
    line = layout.row_line(1, ['apple'])
    assert_includes line, 'apple'
    assert_equal 60, Rufio::TextUtils.display_width(line)
  end

  # === 可視列・横スクロール ===

  def test_all_columns_visible_when_wide_enough
    layout = Rufio::TableLayout.build(wide_sheet, 80)
    assert_equal [0, 1, 2], layout.visible_columns
    assert_equal 0, layout.hidden_column_count
  end

  def test_narrow_width_hides_right_columns
    layout = Rufio::TableLayout.build(wide_sheet, 24)
    assert_equal [0, 1], layout.visible_columns
    assert_equal 1, layout.hidden_column_count
  end

  def test_column_offset_scrolls_horizontally
    layout = Rufio::TableLayout.build(wide_sheet, 24)
    assert_equal [1, 2], layout.visible_columns(1)
    assert_equal 1, layout.hidden_column_count(1), '左に隠れた 1 列を数えること'
  end

  def test_at_least_one_column_is_visible
    layout = Rufio::TableLayout.build(wide_sheet, 8)
    assert_equal 1, layout.visible_columns.length
  end

  def test_gutter_is_dropped_when_too_narrow
    assert_equal 0, Rufio::TableLayout.build(wide_sheet, 8).gutter_width
    assert_operator Rufio::TableLayout.build(wide_sheet, 60).gutter_width, :>, 0
  end

  def test_column_x_points_at_the_cell_body
    layout = Rufio::TableLayout.build(wide_sheet, 80)
    line = layout.row_line(1, %w[apple 120 30])

    x = layout.column_x(1)
    refute_nil x
    assert_equal '120', line[x, 3], 'column_x はセル本体の先頭を指すこと'
  end

  def test_column_x_is_nil_for_hidden_columns
    layout = Rufio::TableLayout.build(wide_sheet, 24)
    assert_nil layout.column_x(2)
  end

  # === offset_for（横スクロール量の計算） ===

  def test_offset_for_keeps_visible_columns_in_place
    layout = Rufio::TableLayout.build(wide_sheet, 80)
    assert_equal 0, layout.offset_for(0, 0)
    assert_equal 0, layout.offset_for(2, 0), '全列見えているならずらさない'
  end

  def test_offset_for_scrolls_right_minimally
    layout = Rufio::TableLayout.build(wide_sheet, 24)
    assert_equal [0, 1], layout.visible_columns(0)
    assert_equal 1, layout.offset_for(2, 0), '1 列だけずらして右端を見せること'
  end

  def test_offset_for_scrolls_back_left
    layout = Rufio::TableLayout.build(wide_sheet, 24)
    assert_equal 0, layout.offset_for(0, 1)
  end

  def test_offset_for_clamps_out_of_range_columns
    layout = Rufio::TableLayout.build(wide_sheet, 24)
    assert_operator layout.offset_for(99, 0), :<=, 2
    assert_equal 0, layout.offset_for(-5, 0)
  end

  def test_offset_for_on_an_empty_sheet
    layout = Rufio::TableLayout.build(sheet(rows: []), 40)
    assert_equal 0, layout.offset_for(0, 0)
  end

  # === plain_lines（lines フォールバック） ===

  def test_plain_lines_includes_header_rows_and_status
    document = Rufio::TableDocument.new(sheets: [wide_sheet])
    lines = Rufio::TableLayout.plain_lines(document, max_lines: 50)

    assert_includes lines.first, 'A name'
    assert(lines.any? { |line| line.include?('apple') })
    assert(lines.any? { |line| line.include?('みかん') })
    assert_includes lines.last, 'rows'
  end

  def test_plain_lines_respects_max_lines
    rows = (1..100).map { |i| [i.to_s, 'x'] }
    document = Rufio::TableDocument.new(sheets: [sheet(header: %w[a b], rows: rows)])
    lines = Rufio::TableLayout.plain_lines(document, max_lines: 10)

    assert_operator lines.length, :<=, 10
  end

  def test_plain_lines_caps_very_wide_tables
    rows = [(1..200).map { |i| "column#{i}" }]
    document = Rufio::TableDocument.new(sheets: [sheet(rows: rows)])
    lines = Rufio::TableLayout.plain_lines(document, max_lines: 5)

    lines.each do |line|
      assert_operator Rufio::TextUtils.display_width(line), :<=, Rufio::TableLayout::PLAIN_MAX_WIDTH
    end
  end

  # === ドキュメントの状態表示 ===

  def test_status_line_reports_rows_and_columns
    document = Rufio::TableDocument.new(sheets: [wide_sheet])
    assert_equal '2 rows  3 cols', document.status_line
  end

  def test_status_line_marks_truncation_and_encoding
    truncated = sheet(header: %w[a], rows: [['1']], row_truncated: true, column_truncated: true)
    document = Rufio::TableDocument.new(sheets: [truncated], encoding: 'CP932', byte_truncated: true)

    status = document.status_line
    assert_includes status, '1+ rows'
    assert_includes status, '1+ cols'
    assert_includes status, 'CP932'
    assert_includes status, 'byte limit reached'
    assert document.truncated?
  end

  def test_status_line_names_the_sheet_when_there_are_several
    document = Rufio::TableDocument.new(
      sheets: [sheet(rows: [['1']], name: 'first'), sheet(rows: [['2']], name: 'second')]
    )
    assert_includes document.status_line(1), '2/2 second'
  end
end
