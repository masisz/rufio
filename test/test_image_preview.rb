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
  include HostOsStub

  def setup
    stub_posix_host_os
    @dir = Dir.mktmpdir('rufio_image_preview')
    @png = write_png('shot.png', 400, 300)
    @jpeg = write_jpeg('photo.jpg', 800, 600)
    File.write(File.join(@dir, 'notes.txt'), "hello\n")
    Rufio::TerminalGraphics.reset!
  end

  def teardown
    Rufio::TerminalGraphics.reset!
    FileUtils.rm_rf(@dir) if @dir
    restore_host_os
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

  # 端末が対応している状態にする。ネイティブのデコードは切って直送経路を見る
  # （ネイティブ経路は test_native_image.rb）
  def with_graphics(supported: true, native: false)
    Rufio::TerminalGraphics.stub(:supported?, supported) do
      Rufio::TerminalGraphics.stub(:protocol, supported ? :kitty : :none) do
        Rufio::NativeImage.stub(:available?, native) { yield }
      end
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

  def test_a_format_that_needs_decoding_is_text_without_the_native_decoder
    with_graphics(native: false) do
      view = Rufio::PreviewView.build(@jpeg)

      assert_instance_of Rufio::ImagePreviewView, view
      refute view.displayable?, 'デコードが使えなければ PNG 以外は表示しないこと'
      assert_includes view.status_line, 'JPEG'
      assert_includes view.status_line, 'unsupported format'
    end
  end

  def test_the_native_decoder_makes_other_formats_displayable
    with_graphics(native: true) do
      assert Rufio::PreviewView.build(@jpeg).displayable?, 'デコードが使えれば JPEG も出せること'
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
    with_graphics(native: false) do
      view = Rufio::PreviewView.build(@png)
      view.stub(:bytes, Rufio::ImagePreviewView::DIRECT_MAX_BYTES + 1) do
        refute view.displayable?, '直送できる上限を超えたら送らないこと'
        assert_includes view.status_line, 'too large'
      end
    end
  end

  def test_a_file_over_the_native_limit_is_not_sent
    with_graphics(native: true) do
      view = Rufio::PreviewView.build(@png)
      view.stub(:bytes, Rufio::ImagePreviewView::NATIVE_MAX_BYTES + 1) do
        refute view.displayable?, 'デコードの上限を超えたら送らないこと'
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

  # デバウンスはここでは 0（別のテストで確認する）
  def layer(debounce: 0)
    Rufio::GraphicsLayer.new(id: 1234, debounce: debounce)
  end

  def request(graphics, payload: 'png-bytes', rect: [5, 3, 40, 20], source: ['a.png', 1], **options)
    row, col, cols, rows = rect
    graphics.request(source: source, payload: payload, row: row, col: col,
                     cols: cols, rows: rows, **options)
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

    output.string = +''
    refute graphics.flush(output), '同じ画像・同じ位置なら送り直さないこと'
    assert_empty output.string
  end

  def test_the_payload_is_only_read_when_it_is_sent
    graphics = layer
    output = StringIO.new
    reads = 0
    graphics.request(source: ['a.png', 1], payload: -> { reads += 1; 'bytes' },
                     row: 1, col: 1, cols: 10, rows: 5)

    assert_equal 0, reads, '申告だけでファイルを読まないこと'
    graphics.flush(output)
    assert_equal 1, reads
    3.times { graphics.flush(output) }
    assert_equal 1, reads, '変化が無ければ読み直さないこと'
  end

  def test_a_payload_that_cannot_be_read_shows_nothing
    graphics = layer
    output = StringIO.new
    attempts = 0
    graphics.request(source: ['a.png', 1], payload: -> { attempts += 1; nil },
                     row: 1, col: 1, cols: 10, rows: 5)

    refute graphics.flush(output)
    refute graphics.placed?

    3.times { graphics.flush(output) }
    assert_equal 1, attempts, '読めなかった画像を毎フレーム読み直さないこと'
  end

  def test_a_different_image_replaces_the_previous_one
    graphics = layer
    output = StringIO.new
    request(graphics)
    graphics.flush(output)

    output.string = +''
    graphics.request(source: ['b.png', 1], payload: 'other', row: 5, col: 3, cols: 40, rows: 20)
    # 1 フレーム目で古い画像を消し、次のフレームで新しい画像を送る
    assert graphics.flush(output)
    assert_includes output.string, 'a=d', '前の画像を消してから送ること'
    refute graphics.placed?

    output.string = +''
    assert graphics.flush(output)
    assert_includes output.string, 'a=T'
    assert graphics.placed?
  end

  def test_moving_the_image_resends_it
    graphics = layer
    output = StringIO.new
    request(graphics)
    graphics.flush(output)

    output.string = +''
    request(graphics, rect: [5, 3, 20, 10])
    assert graphics.flush(output)
    assert_includes output.string, 'c=20'
  end

  def test_no_request_removes_the_image
    graphics = layer
    output = StringIO.new
    request(graphics)
    graphics.flush(output)

    output.string = +''
    graphics.clear
    assert graphics.flush(output)
    assert_includes output.string, 'a=d'
    refute graphics.placed?

    output.string = +''
    refute graphics.flush(output), '消した後は何も出さないこと'
  end

  def test_clear_all_removes_every_image
    graphics = layer
    output = StringIO.new
    request(graphics)
    graphics.flush(output)

    output.string = +''
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

  # === Phase 2: 上書きされたら送り直す ===

  def test_the_image_is_resent_when_its_rows_are_painted_over
    graphics = layer
    output = StringIO.new
    request(graphics, rect: [5, 3, 40, 20]) # 端末座標 5 行目から 20 行
    graphics.flush(output)

    output.string = +''
    refute graphics.flush(output, rewritten_rows: [0, 1, 2]), '矩形の外なら送り直さないこと'
    assert_empty output.string

    assert graphics.flush(output, rewritten_rows: [10]), '矩形の中が書き換わったら送り直すこと'
    assert_includes output.string, 'a=T'
  end

  def test_rows_just_outside_the_rect_do_not_resend
    graphics = layer
    output = StringIO.new
    request(graphics, rect: [5, 3, 40, 3]) # 画面行 4..6
    graphics.flush(output)

    output.string = +''
    refute graphics.flush(output, rewritten_rows: [3, 7])
    assert graphics.flush(output, rewritten_rows: [6])
  end

  def test_unscaled_image_still_detects_paint_over_using_area_rows
    graphics = layer
    output = StringIO.new
    graphics.request(source: ['a.png', 1], payload: 'png-bytes',
                     row: 5, col: 3, cols: nil, rows: nil, area_rows: 3)
    assert graphics.flush(output)
    refute_match(/(?:\A|,)c=/, output.string)
    refute_match(/(?:\A|,)r=/, output.string)

    output.string = +''
    refute graphics.flush(output, rewritten_rows: [3, 7])
    assert graphics.flush(output, rewritten_rows: [5]), 'area_rows の範囲が書き換わったら再送すること'
  end

  # === Phase 2: デバウンス ===

  def test_switching_files_removes_the_old_image_and_waits
    graphics = layer(debounce: 0.08)
    output = StringIO.new
    request(graphics, source: ['a.png', 1])
    graphics.flush(output, now: 0.0)
    assert graphics.placed?

    # 別のファイルへ移動: まず古い画像を消す
    output.string = +''
    request(graphics, source: ['b.png', 1], payload: 'other', now: 0.1)

    assert graphics.flush(output, now: 0.1)
    assert_includes output.string, 'a=d'
    refute_includes output.string, 'a=T', 'すぐには送らないこと'
    refute graphics.placed?

    # デバウンスの間は送らない
    output.string = +''
    refute graphics.flush(output, now: 0.15)
    assert_empty output.string

    # 待ち時間が過ぎたら送る
    assert graphics.flush(output, now: 0.2)
    assert_includes output.string, 'a=T'
    assert graphics.placed?
  end

  def test_the_first_image_is_sent_right_away
    graphics = layer(debounce: 0.08)
    output = StringIO.new
    request(graphics, now: 0.0)

    assert graphics.flush(output, now: 0.0), '最初の 1 枚は待たせないこと'
    assert_includes output.string, 'a=T'
  end

  def test_moving_the_same_image_is_not_debounced
    graphics = layer(debounce: 0.08)
    output = StringIO.new
    request(graphics, now: 0.0)
    graphics.flush(output, now: 0.0)

    output.string = +''
    request(graphics, rect: [5, 3, 20, 10], now: 0.1)
    assert graphics.flush(output, now: 0.1), '同じ画像の置き直しは待たせないこと'
    assert_includes output.string, 'c=20'
  end

  def test_the_debounce_survives_the_per_frame_clear
    graphics = layer(debounce: 0.08)
    output = StringIO.new
    # 描画側は毎フレーム clear → request の順で呼ぶ
    frame = lambda do |source, now|
      graphics.clear
      request(graphics, source: source, now: now)
      graphics.flush(output, now: now)
    end

    frame.call(['a.png', 1], 0.0)
    assert graphics.placed?

    output.string = +''
    assert frame.call(['b.png', 1], 0.1), '古い画像を消すこと'
    assert_includes output.string, 'a=d'

    output.string = +''
    refute frame.call(['b.png', 1], 0.14), '待ち時間の間は送らないこと'
    assert_empty output.string

    assert frame.call(['b.png', 1], 0.2)
    assert_includes output.string, 'a=T'
  end

  # === Phase 2: キャッシュ ===

  def test_the_payload_is_not_read_again_for_the_same_file
    graphics = layer
    output = StringIO.new
    reads = 0
    payload = -> { reads += 1; 'bytes-a' }

    graphics.request(source: ['a.png', 1], payload: payload, row: 1, col: 1, cols: 10, rows: 5)
    graphics.flush(output)
    2.times do
      graphics.request(source: ['b.png', 1], payload: -> { 'bytes-b' }, row: 1, col: 1, cols: 10, rows: 5)
      graphics.flush(output)
    end
    # 同じファイルに戻る
    2.times do
      graphics.request(source: ['a.png', 1], payload: payload, row: 1, col: 1, cols: 10, rows: 5)
      graphics.flush(output)
    end

    assert_equal 1, reads, '一度読んだ画像は覚えておくこと'
  end

  def test_a_changed_file_is_read_again
    graphics = layer
    output = StringIO.new
    reads = 0
    graphics.request(source: ['a.png', 1], payload: -> { reads += 1; 'v1' }, row: 1, col: 1, cols: 10, rows: 5)
    graphics.flush(output)
    # mtime が変わったら別の画像として扱う（1 フレーム目は古い画像の削除）
    graphics.request(source: ['a.png', 2], payload: -> { reads += 1; 'v2' }, row: 1, col: 1, cols: 10, rows: 5)
    2.times { graphics.flush(output) }

    assert_equal 2, reads
  end

  def test_the_cache_keeps_only_a_few_images
    graphics = Rufio::GraphicsLayer.new(id: 1, debounce: 0, cache_entries: 2)
    output = StringIO.new
    reads = Hash.new(0)
    # 実際のループと同じく、1 フレームに 1 回 request / flush する
    show = lambda do |name|
      2.times do
        graphics.request(source: [name, 1], payload: -> { reads[name] += 1; name },
                         row: 1, col: 1, cols: 4, rows: 2)
        graphics.flush(output)
      end
    end

    %w[a b c a].each { |name| show.call(name) }

    assert_equal 2, reads['a'], '古い画像は捨てられるので読み直すこと'
    assert_equal 1, reads['b']
  end

  def test_a_huge_image_is_not_cached
    graphics = Rufio::GraphicsLayer.new(id: 1, debounce: 0, cache_bytes: 16)
    output = StringIO.new
    reads = 0
    payload = -> { reads += 1; 'x' * 64 }

    2.times do
      2.times do
        graphics.request(source: ['a.png', 1], payload: payload, row: 1, col: 1, cols: 4, rows: 2)
        graphics.flush(output)
      end
      2.times do
        graphics.request(source: ['b.png', 1], payload: -> { 'y' }, row: 1, col: 1, cols: 4, rows: 2)
        graphics.flush(output)
      end
    end

    assert_equal 2, reads, '上限を超える画像は覚えないこと'
  end

  # === UIRenderer との結線 ===

  def renderer_for(name, width: 100, height: 20,
                   graphics: Rufio::GraphicsLayer.new(id: 77, debounce: 0))
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

  def test_the_image_shows_in_the_split_pane_too
    with_graphics do
      screen, ui, handler, graphics = renderer_for('shot.png')
      # プレビューモードに入らず（分割表示のまま）描く
      refute handler.preview_focused?
      ui.draw_screen(screen)
      output = StringIO.new

      assert graphics.flush(output), '分割表示でも画像を送ること'
      assert_includes output.string, 'a=T'
      cols = output.string[/c=(\d+)/, 1].to_i
      assert_operator cols, :>, 0
      assert_operator cols, :<, 100, 'ペインの幅に収めること'
    end
  end

  def test_moving_to_another_file_removes_the_image
    with_graphics do
      screen, ui, handler, graphics = renderer_for('shot.png')
      ui.draw_screen(screen)
      graphics.flush(StringIO.new)

      handler.select_index(handler.get_active_entries.index { |entry| entry[:name] == 'notes.txt' })
      screen.clear
      ui.draw_screen(screen)
      output = StringIO.new

      assert graphics.flush(output)
      assert_includes output.string, 'a=d', '画像でないファイルに移ったら消すこと'
    end
  end

  def test_an_overlay_hides_the_image
    with_graphics do
      ui = Rufio::TerminalUI.new(test_mode: true)
      graphics = Rufio::GraphicsLayer.new(id: 55)
      ui.instance_variable_set(:@graphics_layer, graphics)
      output = StringIO.new
      graphics.request(source: ['a.png', 1], payload: 'x', row: 1, col: 1, cols: 10, rows: 5)
      graphics.flush(output)

      output.string = +''
      ui.stub(:help_dialog_active?, true) { ui.send(:flush_graphics, output) }

      assert_includes output.string, 'a=d', 'ヘルプを開いている間は画像を消すこと'
      refute graphics.placed?
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

  # === アスペクト比保持（画面に無理にフィットさせない） ===

  def test_a_large_image_preserves_its_aspect_ratio_instead_of_stretching_to_the_pane
    # 100x20 の画面、フルスクリーン（safe_width=100, rows=15, 既定セル 8x16 → ペイン 800x240 px）
    # 400x300 (4:3) を高さ 240px に収めると 320x240px → 40x15 セル（100x15 に引き伸ばさない）
    with_graphics do
      screen, ui, handler, graphics = renderer_for('shot.png', width: 100, height: 20)
      handler.focus_preview_pane
      ui.draw_screen(screen)
      output = StringIO.new

      assert graphics.flush(output)
      cols = output.string[/c=(\d+)/, 1].to_i
      rows = output.string[/r=(\d+)/, 1].to_i
      assert_equal 15, rows
      assert_equal 40, cols, 'ペイン全幅(100)に引き伸ばさず 4:3 の幅に収めること'
    end
  end

  def test_a_small_image_is_not_stretched_to_fit_the_pane
    write_png('tiny.png', 80, 64) # 既定セル 8x16 なら 10x4 セル相当（ペイン 100x16 よりずっと小さい）
    with_graphics do
      screen, ui, handler, graphics = renderer_for('tiny.png', width: 100, height: 20)
      handler.focus_preview_pane
      ui.draw_screen(screen)
      output = StringIO.new

      assert graphics.flush(output)
      cols = output.string[/c=(\d+)/, 1].to_i
      rows = output.string[/r=(\d+)/, 1].to_i
      assert_equal 10, cols, '小さい画像をペイン幅まで拡大しないこと'
      assert_equal 4, rows, '小さい画像をペイン高さまで拡大しないこと'
    end
  end

  def test_an_image_within_the_pane_omits_c_and_r_when_cell_pixels_are_known
    write_png('tiny.png', 80, 64)
    # CSI 16t でセル寸法（10x20）が取得済みの状態にする
    Rufio::TerminalGraphics.detect!(
      input: StringIO.new("\e_Gi=31;OK\e\\\e[6;20;10t\e[?62;c"),
      output: StringIO.new,
      env: {},
      timeout: 0.05
    )
    Rufio::NativeImage.stub(:available?, false) do
      screen, ui, handler, graphics = renderer_for('tiny.png', width: 100, height: 20)
      handler.focus_preview_pane
      ui.draw_screen(screen)
      output = StringIO.new

      assert graphics.flush(output)
      refute_match(/(?:\A|,)c=/, output.string, 'ペイン内に収まる画像は c= を付けず実ピクセルで出すこと')
      refute_match(/(?:\A|,)r=/, output.string, 'ペイン内に収まる画像は r= を付けず実ピクセルで出すこと')
    end
  end

  # === セキュリティ ===

  def test_direct_read_enforces_size_limit_even_if_file_grows_after_header_read
    with_graphics(native: false) do
      view = Rufio::PreviewView.build(@png)
      # ヘッダ読み込み後にファイルが上限を超えて肥大化した（TOCTOU）ケースを再現
      oversized = 'x' * (Rufio::ImagePreviewView::DIRECT_MAX_BYTES + 1)
      File.stub(:binread, ->(_path, _len = nil) { oversized }) do
        assert_nil view.transfer[:payload].call, '上限超過ファイルは読み込まず nil を返すこと'
      end
    end
  end
end
