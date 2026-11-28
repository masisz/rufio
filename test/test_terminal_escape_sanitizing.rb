# frozen_string_literal: true

require 'minitest/autorun'
require 'fileutils'
require 'tmpdir'
require_relative '../lib/rufio'

# 端末制御シーケンスの無害化。
# ファイル名・ファイル内容・外部コマンドの出力は信用できないため、画面に出す前に
# 制御文字を落とす。OSC 52（クリップボード書き換え）や画面消去が端末へ届かないこと。
class TestTerminalEscapeSanitizing < Minitest::Test
  OSC52 = "\e]52;c;cHduZWQ=\a"

  def setup
    @dir = Dir.mktmpdir('rufio_escape_test')
  end

  def teardown
    FileUtils.rm_rf(@dir) if @dir && Dir.exist?(@dir)
  end

  # === TextUtils.sanitize_for_display ===

  def test_control_characters_become_spaces
    {
      "a\eb" => 'a b',
      "a\ab" => 'a b',
      "a\u0000b" => 'a b',
      "a\tb" => 'a b',
      "a\nb" => 'a b',
      "a\u009bb" => 'a b' # 8 ビットの CSI
    }.each do |input, expected|
      assert_equal expected, Rufio::TextUtils.sanitize_for_display(input), input.inspect
    end
  end

  def test_escape_sequences_are_broken_up
    sanitized = Rufio::TextUtils.sanitize_for_display("x#{OSC52}y")
    refute_includes sanitized, "\e"
    refute_includes sanitized, "\a"
    assert_includes sanitized, 'x'
  end

  def test_ordinary_text_is_untouched
    %w[apple みかん ①②③].each do |text|
      assert_same text, Rufio::TextUtils.sanitize_for_display(text), '制御文字がなければ同じ文字列を返す'
    end
  end

  def test_invalid_bytes_are_replaced
    result = Rufio::TextUtils.sanitize_for_display("a\xFF\xFEb".dup.force_encoding('UTF-8'))
    assert result.valid_encoding?
    assert_includes result, 'a'
  end

  def test_control_char_predicate
    assert Rufio::TextUtils.control_char?("\e")
    assert Rufio::TextUtils.control_char?("\u009b")
    refute Rufio::TextUtils.control_char?('a')
    refute Rufio::TextUtils.control_char?('　')
    refute Rufio::TextUtils.control_char?('')
  end

  # === Screen（描画の合流点） ===

  def test_put_string_drops_escape_sequences
    screen = Rufio::Screen.new(60, 1)
    screen.put_string(0, 0, "name#{OSC52}end")
    rendered = screen.row(0)

    refute_includes rendered, "\e]", 'OSC シーケンスが残らないこと'
    refute_includes rendered, "\a"
    assert_includes rendered, 'name'
  end

  def test_put_string_drops_csi_sequences_that_are_not_colours
    screen = Rufio::Screen.new(60, 1)
    screen.put_string(0, 0, "a\e[2J\e[?1049hb")
    refute_includes screen.row(0), "\e"
  end

  def test_put_string_still_applies_requested_colours
    screen = Rufio::Screen.new(20, 1)
    screen.put_string(0, 0, 'text', fg: "\e[31m")
    assert_includes screen.row(0), "\e[31m", '引数で渡した色は残ること'
  end

  def test_put_drops_a_single_control_character
    screen = Rufio::Screen.new(10, 1)
    screen.put(0, 0, "\e")
    screen.put(1, 0, 'a')

    refute_includes screen.row(0), "\e"
    assert_equal 1, screen.get_cell(0, 0)[:width], '置き換えた空白の幅で数えること'
  end

  # === 表プレビュー（セル・見出し・シート名） ===

  def sheet_with(rows:, header: nil, name: 'test.csv')
    Rufio::MemoryTableSheet.new(rows: rows, header: header, name: name)
  end

  def test_cell_values_are_sanitized_in_the_grid
    layout = Rufio::TableLayout.build(sheet_with(rows: [["x#{OSC52}y"]]), 60)
    line = layout.row_line(1, ["x#{OSC52}y"])

    refute_includes line, "\e"
    refute_includes line, "\a"
  end

  def test_header_text_is_sanitized_in_the_grid
    sheet = sheet_with(header: ["h#{OSC52}"], rows: [['v']])
    refute_includes Rufio::TableLayout.build(sheet, 60).header_line, "\e"
    refute_includes sheet.column_title(0), "\e"
  end

  def test_sheet_name_is_sanitized_in_the_status_line
    document = Rufio::TableDocument.new(
      sheets: [sheet_with(rows: [['a']], name: 'first'),
               sheet_with(rows: [['b']], name: "second#{OSC52}")]
    )
    refute_includes document.status_line(1), "\e"
    assert_includes document.status_line(1), 'second'
  end

  def test_load_error_is_sanitized_in_the_status_line
    sheet = Rufio::LazyTableSheet.new(name: 'boom') { raise "broken#{OSC52}" }
    document = Rufio::TableDocument.new(sheets: [sheet])

    refute_includes document.status_line, "\e"
  end

  def test_cell_address_is_sanitized_in_the_preview_status
    path = File.join(@dir, 'evil.tsv')
    File.write(path, "col\th#{OSC52}\nv1\tv2\n")
    view = Rufio::PreviewView.build(path)
    view.handle_key('l')

    refute_includes view.status_line, "\e"
    assert_includes view.status_line, 'R1C2'
  end

  # === 画面全体（カーソルを合わせるだけで届かないこと） ===

  def render(name, focus:)
    listing = Rufio::DirectoryListing.new(@dir)
    handler = Rufio::KeybindHandler.new
    handler.set_directory_listing(listing)
    index = listing.list_entries.index { |entry| entry[:name] == name }
    refute_nil index, "#{name} が一覧にあること"
    handler.select_index(index)

    screen = Rufio::Screen.new(100, 24)
    ui = Rufio::UIRenderer.new(screen_width: 100, screen_height: 24,
                               keybind_handler: handler, directory_listing: listing,
                               file_preview: Rufio::FilePreview.new)
    handler.focus_preview_pane if focus
    ui.draw_screen(screen)
    (0...24).map { |y| screen.row(y) }.join("\n")
  end

  def test_table_cell_does_not_reach_the_terminal
    File.write(File.join(@dir, 'evil.tsv'), "col\tnote\nvalue\t#{OSC52}\n")

    [true, false].each do |focus|
      refute_includes render('evil.tsv', focus: focus), OSC52,
                      "focus=#{focus} でもエスケープが届かないこと"
    end
  end

  def test_text_preview_does_not_reach_the_terminal
    File.write(File.join(@dir, 'evil.txt'), "line\n#{OSC52}\n")

    refute_includes render('evil.txt', focus: true), OSC52
    refute_includes render('evil.txt', focus: false), OSC52
  end

  def test_file_name_does_not_reach_the_terminal
    skip 'Windows ではファイル名に制御文字を使えない' if windows_platform?

    File.write(File.join(@dir, "inno#{OSC52}cent.txt"), 'x')
    File.write(File.join(@dir, 'plain.txt'), 'x')

    refute_includes render('plain.txt', focus: false), OSC52
  end

  def test_a_csv_full_of_control_bytes_is_rendered_without_escapes
    # 制御文字比率が高く、以前はバイナリ判定で弾かれていた内容
    File.write(File.join(@dir, 'dense.csv'), "a,b\n#{"\e" * 40},#{"\e" * 40}\n")
    preview = Rufio::FilePreview.new.preview_file(File.join(@dir, 'dense.csv'))

    assert_equal 'table', preview[:type]
    refute_includes preview[:lines].join, "\e", 'lines フォールバックにも残らないこと'
    refute_includes render('dense.csv', focus: true), "\e]"
  end
end
