# frozen_string_literal: true

require_relative 'test_helper'
require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'stringio'
require_relative '../lib/rufio'

# 画像プレビューのズーム（`+` / `-` / `0`）と、ズーム中の移動（hjkl）。
# 拡大は元画像の一部を切り出して同じセル矩形に出す方式で、デコードは要らない。
class TestImageZoom < Minitest::Test
  def setup
    @dir = Dir.mktmpdir('rufio_image_zoom')
    @png = write_png('shot.png', 400, 300)
    # 端末が対応している状態にする（応答を与えて本物の判定を通す）
    Rufio::TerminalGraphics.reset!
    support(true)
  end

  # @param supported [Boolean] 問い合わせに OK を返す端末として判定させる
  def support(supported)
    Rufio::TerminalGraphics.reset!
    answer = supported ? "\e_Gi=31;OK\e\\\e[?62;c" : "\e[?62;c"
    Rufio::TerminalGraphics.detect!(input: StringIO.new(answer), output: StringIO.new,
                                   env: {}, timeout: 0.05)
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

  def view
    Rufio::PreviewView.build(@png)
  end

  def zoomed_view(steps = 1)
    v = view
    steps.times { v.handle_key('+') }
    v
  end

  # === ズーム ===

  def test_the_image_fits_the_pane_by_default
    v = view

    assert_equal 1.0, v.zoom
    assert_nil v.crop, '等倍（収まり）では切り出さないこと'
  end

  def test_plus_and_minus_change_the_zoom_in_steps
    v = view

    assert v.handle_key('+')
    assert_in_delta 1.25, v.zoom
    assert v.handle_key('+')
    assert_in_delta 1.5, v.zoom
    assert v.handle_key('-')
    assert_in_delta 1.25, v.zoom
  end

  def test_zoom_stops_at_fit_and_at_the_maximum
    v = view

    refute v.handle_key('-'), '収まりより小さくはしない'
    assert_equal 1.0, v.zoom

    40.times { v.handle_key('+') }
    assert_equal Rufio::ImagePreviewView::MAX_ZOOM, v.zoom
    refute v.handle_key('+')
  end

  def test_zero_returns_to_fit
    v = zoomed_view(3)
    assert_operator v.zoom, :>, 1.0

    assert v.handle_key('0')
    assert_equal 1.0, v.zoom
    assert_nil v.crop
  end

  def test_the_crop_is_centred_and_scaled
    v = zoomed_view(4) # 2.0 倍
    x, y, w, h = v.crop

    assert_in_delta 200, w, 1, '2 倍なら元の半分の幅を出す'
    assert_in_delta 150, h, 1
    assert_in_delta 100, x, 1, '中央を切り出すこと'
    assert_in_delta 75, y, 1
  end

  # === ズーム中の移動 ===

  def test_hjkl_pans_the_cropped_area
    v = zoomed_view(4)
    x, y, = v.crop

    assert v.handle_key('l')
    assert_operator v.crop[0], :>, x, 'l で右へ'
    assert v.handle_key('h')
    assert_in_delta x, v.crop[0], 1

    assert v.handle_key('j')
    assert_operator v.crop[1], :>, y, 'j で下へ'
    assert v.handle_key('k')
    assert_in_delta y, v.crop[1], 1
  end

  def test_arrow_keys_pan_too
    v = zoomed_view(4)
    x, = v.crop
    v.handle_key("\e[C")

    assert_operator v.crop[0], :>, x
  end

  def test_panning_stops_at_the_edges
    v = zoomed_view(4)
    20.times { v.handle_key('l') }
    x, _y, w, = v.crop

    assert_equal 400, x + w, '右端を越えないこと'
    20.times { v.handle_key('h') }
    assert_equal 0, v.crop[0], '左端を越えないこと'
  end

  def test_panning_does_nothing_without_zoom
    v = view

    refute v.handle_key('l')
    refute v.handle_key('j')
    assert_nil v.crop
  end

  def test_zooming_back_to_fit_forgets_the_pan
    v = zoomed_view(4)
    5.times { v.handle_key('l') }
    v.handle_key('0')
    v.handle_key('+')
    v.handle_key('+')
    v.handle_key('+')
    v.handle_key('+')

    assert_in_delta 100, v.crop[0], 1, '中央に戻ること'
  end

  # === 表示できないときはズームしない ===

  def test_zoom_is_off_when_the_image_cannot_be_shown
    support(false)
    v = view

    refute v.handle_key('+')
    assert_equal 1.0, v.zoom
    assert_nil v.crop
  end

  def test_zoom_is_off_without_known_dimensions
    path = File.join(@dir, 'no_size.jpg')
    File.binwrite(path, "\xff\xd8".b + ("\x00".b * 32))
    v = Rufio::PreviewView.build(path)

    refute v.handle_key('+')
    assert_nil v.crop
  end

  # === ステータス行 ===

  def test_the_status_line_shows_the_zoom_and_the_hints
    v = view
    assert_includes v.status_line, '+/-: zoom'
    refute_includes v.status_line, '100%', '収まりのときは倍率を出さない'

    v.handle_key('+')
    assert_includes v.status_line, '125%'
    assert_includes v.status_line, 'hjkl: pan'
  end

  def test_reset_returns_to_fit
    v = zoomed_view(2)
    assert v.reset

    assert_equal 1.0, v.zoom
    assert_nil v.crop
  end

  # === 描画への反映 ===

  def test_the_crop_is_sent_to_the_terminal
    begin
      begin
        screen = Rufio::Screen.new(100, 20)
        listing = Rufio::DirectoryListing.new(@dir)
        handler = Rufio::KeybindHandler.new
        handler.set_directory_listing(listing)
        graphics = Rufio::GraphicsLayer.new(id: 9, debounce: 0)
        ui = Rufio::UIRenderer.new(screen_width: 100, screen_height: 20,
                                   keybind_handler: handler, directory_listing: listing,
                                   file_preview: Rufio::FilePreview.new, graphics_layer: graphics)
        handler.select_index(listing.list_entries.index { |entry| entry[:name] == 'shot.png' })
        assert handler.focus_preview_pane

        ui.draw_screen(screen)
        graphics.flush(StringIO.new)

        4.times { handler.handle_key('+') }
        screen.clear
        ui.draw_screen(screen)
        output = StringIO.new
        assert graphics.flush(output), 'ズームしたら送り直すこと'
        assert_match(/x=100/, output.string)
        assert_match(/w=200/, output.string)
      end
    end
  end
end
