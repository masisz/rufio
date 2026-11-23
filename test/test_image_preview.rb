# frozen_string_literal: true

require_relative 'test_helper'
require 'minitest/autorun'
require 'stringio'
require 'tmpdir'
require 'fileutils'
require_relative '../lib/rufio'

# 画像プレビュー（Phase 1: PNG 直送）。
# セルは空白で確保し、画像は差分レンダリングの後に APC で送る。
class TestImagePreview < Minitest::Test
  def setup
    @dir = Dir.mktmpdir('rufio_image_preview')
    @png = write_png('shot.png', 400, 300)
    @jpeg = write_jpeg('photo.jpg', 800, 600)
    File.write(File.join(@dir, 'notes.txt'), "hello\n")
    Rufio::TerminalGraphics.reset!
  end

  def teardown
    Rufio::TerminalGraphics.reset!
    FileUtils.rm_rf(@dir) if @dir
  end

  def write_png(name, width, height)
    path = File.join(@dir, name)
    ihdr = [13].pack('N') + 'IHDR' + [width, height].pack('NN') + "\x08\x06\x00\x00\x00".b + [0].pack('N')
    File.binwrite(path, "\x89PNG\r\n\x1a\n".b + ihdr + ("\x00".b * 32))
    path
  end

  def write_jpeg(name, width, height)
    path = File.join(@dir, name)
    sof0 = "\xff\xc0".b + [17].pack('n') + "\x08".b + [height, width].pack('nn') + "\x03".b + ("\x00".b * 9)
    File.binwrite(path, "\xff\xd8".b + sof0 + "\xff\xd9".b)
    path
  end

  # 端末が対応している状態にする
  def with_graphics(supported: true)
    Rufio::TerminalGraphics.stub(:supported?, supported) do
      Rufio::TerminalGraphics.stub(:protocol, supported ? :kitty : :none) { yield }
    end
  end

  # === ビュー ===

  def test_an_image_file_gets_the_image_view
    with_graphics do
      view = Rufio::PreviewView.build(@png)

      assert_instance_of Rufio::ImagePreviewView, view
      assert view.image?
      refute view.table?
      assert_equal :png, view.info.kind
    end
  end

  def test_a_text_file_is_not_an_image_view
    with_graphics do
      assert_instance_of Rufio::TextPreviewView, Rufio::PreviewView.build(File.join(@dir, 'notes.txt'))
    end
  end

  def test_the_view_is_used_even_when_the_terminal_cannot_show_images
    with_graphics(supported: false) do
      view = Rufio::PreviewView.build(@png)

      assert_instance_of Rufio::ImagePreviewView, view
      refute view.displayable?, '非対応端末では画像を送らないこと'
      assert_includes view.status_line, 'no image support'
    end
  end

  def test_the_status_line_describes_the_image
    with_graphics do
      view = Rufio::PreviewView.build(@png)

      assert_includes view.status_line, 'PNG'
      assert_includes view.status_line, '400x300'
      assert_includes view.status_line, 'ESC'
    end
  end

  def test_a_format_that_needs_decoding_is_reported_in_phase_one
    with_graphics do
      view = Rufio::PreviewView.build(@jpeg)

      assert_instance_of Rufio::ImagePreviewView, view
      refute view.displayable?, 'PNG 以外は（デコードが入るまで）表示しないこと'
      assert_includes view.status_line, 'JPEG'
    end
  end

  def test_the_view_copies_the_path_and_ignores_other_keys
    with_graphics do
      view = Rufio::PreviewView.build(@png)
      copied = []
      Rufio::Clipboard.stub(:copy, ->(text) { copied << text; :pbcopy }) { assert view.handle_key('y') }

      assert_equal [File.expand_path(@png)], copied
      refute view.handle_key('j'), 'スクロールしないこと'
      refute view.handle_key('/'), '画像では検索しないこと'
      refute view.handle_key("\e"), 'ESC はプレビューを抜ける（ビューでは扱わない）'
    end
  end

  def test_a_file_over_the_direct_limit_is_not_sent
    with_graphics do
      view = Rufio::PreviewView.build(@png)
      view.stub(:bytes, Rufio::ImagePreviewView::DIRECT_MAX_BYTES + 1) do
        refute view.displayable?
        assert_includes view.status_line, 'too large'
      end
    end
  end

  # === Screen#reserve ===

  def test_reserved_cells_reject_writes
    screen = Rufio::Screen.new(20, 5)
    screen.reserve(4, 1, 6, 2)
    screen.put_string(0, 1, 'x' * 20)

    row = screen.row(1)
    assert_equal 'xxxx      xxxxxxxxxx', Rufio::ColorHelper.strip_ansi(row)
    screen.put(5, 2, 'y')
    assert_equal ' ', screen.get_cell(5, 2)[:char]
  end

  def test_clearing_the_screen_drops_the_reservation
    screen = Rufio::Screen.new(10, 3)
    screen.reserve(0, 0, 10, 3)
    screen.clear
    screen.put_string(0, 0, 'ok')

    assert_includes Rufio::ColorHelper.strip_ansi(screen.row(0)), 'ok'
  end

  # === Renderer は書き換えた行を返す ===

  def test_the_renderer_reports_the_rows_it_wrote
    output = StringIO.new
    renderer = Rufio::Renderer.new(10, 4, output: output)
    screen = Rufio::Screen.new(10, 4)
    screen.put_string(0, 2, 'hi')

    assert_equal [2], renderer.render(screen)
    assert_empty renderer.render(screen), '変化が無ければ空を返すこと'
  end

  # === GraphicsLayer ===

  def layer
    Rufio::GraphicsLayer.new(id: 1234)
  end

  def request(graphics, payload: 'png-bytes', rect: [5, 3, 40, 20])
    row, col, cols, rows = rect
    graphics.request(key: ['a.png', 1, rect], payload: payload, row: row, col: col, cols: cols, rows: rows)
  end

  def test_the_layer_sends_the_image_once
    graphics = layer
    output = StringIO.new
    request(graphics)

    assert graphics.flush(output)
    assert_includes output.string, 'a=T'
    assert_includes output.string, 'i=1234'
    assert_includes output.string, 'c=40'
    assert_includes output.string, "\e[5;3H"

    output.string = ''
    refute graphics.flush(output), '同じ画像・同じ位置なら送り直さないこと'
    assert_empty output.string
  end

  def test_a_different_image_replaces_the_previous_one
    graphics = layer
    output = StringIO.new
    request(graphics)
    graphics.flush(output)

    output.string = ''
    graphics.request(key: ['b.png', 1, [5, 3, 40, 20]], payload: 'other', row: 5, col: 3, cols: 40, rows: 20)
    assert graphics.flush(output)
    assert_includes output.string, 'a=d', '前の画像を消してから送ること'
    assert_includes output.string, 'a=T'
  end

  def test_moving_the_image_resends_it
    graphics = layer
    output = StringIO.new
    request(graphics)
    graphics.flush(output)

    output.string = ''
    request(graphics, rect: [5, 3, 20, 10])
    assert graphics.flush(output)
    assert_includes output.string, 'c=20'
  end

  def test_no_request_removes_the_image
    graphics = layer
    output = StringIO.new
    request(graphics)
    graphics.flush(output)

    output.string = ''
    graphics.clear
    assert graphics.flush(output)
    assert_includes output.string, 'a=d'
    refute graphics.placed?

    output.string = ''
    refute graphics.flush(output), '消した後は何も出さないこと'
  end

  def test_clear_all_removes_every_image
    graphics = layer
    output = StringIO.new
    request(graphics)
    graphics.flush(output)

    output.string = ''
    graphics.clear_all(output)
    assert_includes output.string, 'd=A'
    refute graphics.placed?
  end

  def test_a_closed_output_does_not_raise
    graphics = layer
    output = StringIO.new
    output.close
    request(graphics)

    refute graphics.flush(output), '書けない端末でも落ちないこと'
  end

  # === UIRenderer との結線 ===

  def renderer_for(name, width: 100, height: 20, graphics: Rufio::GraphicsLayer.new(id: 77))
    screen = Rufio::Screen.new(width, height)
    listing = Rufio::DirectoryListing.new(@dir)
    handler = Rufio::KeybindHandler.new
    handler.set_directory_listing(listing)
    ui = Rufio::UIRenderer.new(screen_width: width, screen_height: height,
                               keybind_handler: handler, directory_listing: listing,
                               file_preview: Rufio::FilePreview.new, graphics_layer: graphics)
    handler.select_index(listing.list_entries.index { |entry| entry[:name] == name })
    [screen, ui, handler, graphics]
  end

  def screen_text(screen, height)
    (0...height).map { |y| Rufio::ColorHelper.strip_ansi(screen.row(y)) }.join("\n")
  end

  def test_the_pane_is_left_blank_and_the_image_is_requested
    with_graphics do
      screen, ui, handler, graphics = renderer_for('shot.png')
      assert handler.focus_preview_pane
      ui.draw_screen(screen)
      output = StringIO.new

      assert graphics.flush(output), '画像を送ること'
      assert_includes output.string, 'a=T'
      # 画像の領域は空白のまま（文字で潰さない）
      text = screen_text(screen, 20).lines[4..-3].join
      assert_equal '', text.strip
      assert_includes screen_text(screen, 20), 'shot.png'
      assert_includes screen_text(screen, 20), '400x300'
    end
  end

  def test_an_unsupported_terminal_shows_the_details_as_text
    with_graphics(supported: false) do
      screen, ui, handler, graphics = renderer_for('shot.png')
      handler.focus_preview_pane
      ui.draw_screen(screen)
      output = StringIO.new

      refute graphics.flush(output), '非対応端末では何も送らないこと'
      text = screen_text(screen, 20)
      assert_includes text, 'PNG'
      assert_includes text, '400x300'
    end
  end

  def test_leaving_the_preview_removes_the_image
    with_graphics do
      screen, ui, handler, graphics = renderer_for('shot.png')
      handler.focus_preview_pane
      ui.draw_screen(screen)
      graphics.flush(StringIO.new)

      handler.handle_key("\e")
      screen.clear
      ui.draw_screen(screen)
      output = StringIO.new

      assert graphics.flush(output)
      assert_includes output.string, 'a=d'
    end
  end

  def test_a_text_file_does_not_request_an_image
    with_graphics do
      screen, ui, handler, graphics = renderer_for('notes.txt')
      handler.focus_preview_pane
      ui.draw_screen(screen)

      refute graphics.flush(StringIO.new)
      assert_includes screen_text(screen, 20), 'hello'
    end
  end
end
