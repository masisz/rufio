# frozen_string_literal: true

require_relative 'test_helper'
require 'minitest/autorun'
require 'stringio'
require 'tmpdir'
require 'fileutils'
require_relative '../lib/rufio'

# Zig 実装の画像デコード（Phase 3）と、それを使うプレビューの組み立て。
# ライブラリが無い環境では native 側のテストをスキップし、フォールバックだけを確認する。
class TestNativeImage < Minitest::Test
  include HostOsStub
  FIXTURES = File.expand_path('fixtures/images', __dir__)
  # fixtures は 16x12 のグラデーション（PNG / JPEG / BMP）と 8x8 の半透明 PNG
  SOURCE = [16, 12].freeze

  def setup
    @dir = Dir.mktmpdir('rufio_native_image')
    %w[gradient.png gradient.jpg gradient.bmp alpha.png].each do |name|
      FileUtils.cp(File.join(FIXTURES, name), File.join(@dir, name))
    end
    File.write(File.join(@dir, 'notes.txt'), "hello\n")
    stub_posix_host_os
    Rufio::TerminalGraphics.reset!
    support_graphics(true)
  end

  def teardown
    Rufio::TerminalGraphics.reset!
    FileUtils.rm_rf(@dir) if @dir
    restore_host_os
  end

  def support_graphics(supported)
    Rufio::TerminalGraphics.reset!
    answer = supported ? "\e_Gi=31;OK\e\\\e[?62;c" : "\e[?62;c"
    Rufio::TerminalGraphics.detect!(input: StringIO.new(answer), output: StringIO.new,
                                   env: {}, timeout: 0.05)
  end

  def path(name)
    File.join(@dir, name)
  end

  def native_or_skip
    skip 'Zig の画像デコードが使えない環境' unless Rufio::NativeImage.available?
  end

  def settle(job, timeout: 5)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    while job.running?
      flunk 'デコードが終わらない' if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      sleep 0.005
    end
    job
  end

  # === NativeImage ===

  def test_each_format_is_decoded_and_scaled_down
    native_or_skip
    %w[gradient.png gradient.jpg gradient.bmp].each do |name|
      job = settle(Rufio::NativeImage.decode(path(name), max_w: 8, max_h: 8))
      begin
        assert job.done?, name
        info = job.info
        assert_equal [8, 6], [info[:width], info[:height]], "#{name}: 比を保って縮小すること"
        assert_equal SOURCE, [info[:src_width], info[:src_height]], name
        refute_empty job.payload, name
        # ペイロードは Base64 済みの PNG
        assert_match(/\A[A-Za-z0-9+\/=]+\z/, job.payload, name)
        assert_equal "\x89PNG".b, job.payload.unpack1('m0')[0, 4], name
      ensure
        job.close
      end
    end
  end

  def test_the_format_is_reported
    native_or_skip
    { 'gradient.png' => :png, 'gradient.jpg' => :jpeg, 'gradient.bmp' => :bmp }.each do |name, kind|
      job = settle(Rufio::NativeImage.decode(path(name), max_w: 8, max_h: 8))
      assert_equal kind, job.info[:kind], name
      job.close
    end
  end

  def test_a_small_image_is_not_scaled_up
    native_or_skip
    job = settle(Rufio::NativeImage.decode(path('gradient.png'), max_w: 200, max_h: 200))

    assert_equal SOURCE, [job.info[:width], job.info[:height]], '拡大はしないこと'
    job.close
  end

  def test_alpha_is_kept
    native_or_skip
    job = settle(Rufio::NativeImage.decode(path('alpha.png'), max_w: 8, max_h: 8))

    assert_equal 4, job.info[:channels], 'アルファのある画像は 4 チャンネルで返すこと'
    job.close
  end

  def test_a_file_that_is_not_an_image_fails_without_raising
    native_or_skip
    job = settle(Rufio::NativeImage.decode(path('notes.txt'), max_w: 8, max_h: 8))

    assert job.failed?
    assert_nil job.info
    assert_nil job.payload
    job.close
  end

  def test_a_missing_file_fails
    native_or_skip
    job = settle(Rufio::NativeImage.decode(path('gone.png'), max_w: 8, max_h: 8))

    assert job.failed?
    job.close
  end

  def test_closing_twice_is_safe
    native_or_skip
    job = settle(Rufio::NativeImage.decode(path('gradient.png'), max_w: 8, max_h: 8))
    job.close
    job.close

    assert job.closed?
    assert_nil job.payload
  end

  def test_cancelling_stops_the_job
    native_or_skip
    job = Rufio::NativeImage.decode(path('gradient.png'), max_w: 8, max_h: 8)
    job.cancel
    settle(job)

    assert_includes [Rufio::NativeImage::STATE_DONE, Rufio::NativeImage::STATE_CANCELLED], job.state
    job.close
  end

  def test_the_environment_variable_turns_the_native_path_off
    original = ENV['RUFIO_NATIVE_IMAGE']
    ENV['RUFIO_NATIVE_IMAGE'] = '0'

    refute Rufio::NativeImage.available?
    assert_nil Rufio::NativeImage.decode(path('gradient.png'), max_w: 8, max_h: 8)
  ensure
    ENV['RUFIO_NATIVE_IMAGE'] = original
  end

  # === ビュー（デコードを使う） ===

  def view_for(name, pixels: [320, 240])
    view = Rufio::PreviewView.build(path(name))
    view.target_pixels = pixels
    view
  end

  def settle_view(view, timeout: 5)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    while view.loading?
      flunk 'デコードが終わらない' if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      sleep 0.005
      view.transfer # ポーリングは transfer 経由
    end
    view
  end

  def test_a_jpeg_can_be_shown_when_the_native_decoder_is_available
    native_or_skip
    view = view_for('gradient.jpg')

    assert view.displayable?, 'JPEG も表示できること'
    assert view.loading?, 'デコード中は loading'
    assert_nil view.transfer
    assert_includes view.status_line, 'decoding'

    settle_view(view)
    transfer = view.transfer
    refute_nil transfer
    assert transfer[:encoded], 'ネイティブ経路のペイロードは Base64 済み'
    assert_equal Rufio::KittyGraphics::FORMAT_PNG, transfer[:format]
    assert_equal "\x89PNG".b, transfer[:payload].unpack1('m0')[0, 4]
    view.release
  end

  def test_the_status_line_shows_the_decoded_size
    native_or_skip
    view = settle_view(view_for('gradient.jpg', pixels: [8, 8]))

    assert_includes view.status_line, 'JPEG 16x12'
    assert_includes view.status_line, '8x6', '縮小後の寸法も出すこと'
    view.release
  end

  def test_a_bmp_can_be_shown
    native_or_skip
    view = settle_view(view_for('gradient.bmp'))

    assert view.displayable?
    refute_nil view.transfer
    view.release
  end

  def test_a_gif_is_still_text_only
    File.binwrite(path('anim.gif'), "GIF89a#{[4, 4].pack('vv')}#{"\x00" * 16}")
    view = view_for('anim.gif')

    refute view.displayable?
    assert_includes view.status_line, 'unsupported format'
    view.release
  end

  def test_without_the_native_decoder_only_png_is_sent
    Rufio::NativeImage.stub(:available?, false) do
      png = view_for('gradient.png')
      assert png.displayable?
      refute png.loading?
      transfer = png.transfer
      refute transfer[:encoded], '直送はファイルのバイト列をそのまま渡す'
      png.release

      jpeg = view_for('gradient.jpg')
      refute jpeg.displayable?, 'デコードできないので JPEG はテキスト表示'
      jpeg.release
    end
  end

  def test_the_decode_follows_the_pane_size
    native_or_skip
    view = settle_view(view_for('gradient.png', pixels: [8, 8]))
    first = view.transfer[:key]
    assert_includes view.status_line, '8x6'

    # ペインが広くなったら、その大きさで取り直す
    view.target_pixels = [16, 16]
    settle_view(view)
    refute_equal first, view.transfer[:key], '矩形が変わったら送り直すこと'
    assert_includes view.status_line, '16x12'
    view.release
  end

  def test_zooming_decodes_at_the_zoomed_resolution
    native_or_skip
    view = settle_view(view_for('gradient.png', pixels: [8, 8]))
    assert_equal [8, 6], view.transmitted_size

    2.times { view.handle_key('+') } # 1.5 倍
    settle_view(view)

    assert_operator view.transmitted_size[0], :>, 8, 'ズーム分だけ細かくデコードすること'
    crop = view.crop
    refute_nil crop
    assert_operator crop[2], :<=, view.transmitted_size[0], '切り出しは転送した画像の内側'
    view.release
  end

  def test_release_closes_the_job
    native_or_skip
    view = view_for('gradient.png')
    view.transfer
    view.release

    refute view.loading?
    assert_nil view.transfer
  end

  # === 描画（UIRenderer） ===

  def renderer_for(name, width: 100, height: 20)
    screen = Rufio::Screen.new(width, height)
    listing = Rufio::DirectoryListing.new(@dir)
    handler = Rufio::KeybindHandler.new
    handler.set_directory_listing(listing)
    graphics = Rufio::GraphicsLayer.new(id: 42, debounce: 0)
    ui = Rufio::UIRenderer.new(screen_width: width, screen_height: height,
                               keybind_handler: handler, directory_listing: listing,
                               file_preview: Rufio::FilePreview.new, graphics_layer: graphics)
    handler.select_index(listing.list_entries.index { |entry| entry[:name] == name })
    [screen, ui, handler, graphics]
  end

  def test_a_jpeg_is_drawn_after_decoding
    native_or_skip
    screen, ui, handler, graphics = renderer_for('gradient.jpg')
    assert handler.focus_preview_pane

    # 1 フレーム目はデコード中
    ui.draw_screen(screen)
    refute graphics.flush(StringIO.new), 'デコード中は送らないこと'
    text = (0...20).map { |y| Rufio::ColorHelper.strip_ansi(screen.row(y)) }.join("\n")
    assert_includes text, 'decoding'

    settle_view(handler.preview_view)
    screen.clear
    ui.draw_screen(screen)
    output = StringIO.new

    assert graphics.flush(output), 'デコードが終わったら送ること'
    assert_includes output.string, 'a=T'
    assert_includes output.string, 'f=100'
  end

  def test_polling_reports_when_background_decoding_finishes
    native_or_skip
    screen, ui, handler, graphics = renderer_for('gradient.jpg')
    assert handler.focus_preview_pane

    # 1 フレーム目はデコード開始（まだ結果はない）
    ui.draw_screen(screen)
    refute graphics.flush(StringIO.new)

    # メインループ相当: 入力が無くても poll_image_preview が完了を検知して true を返す
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
    ready = false
    until ready
      flunk 'poll_image_preview が完了を報告しない' if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      ready = ui.poll_image_preview
      sleep 0.005 unless ready
    end

    # 完了検知後の 2 回目は false（不要な再描画を繰り返さない）
    refute ui.poll_image_preview

    screen.clear
    ui.draw_screen(screen)
    output = StringIO.new
    assert graphics.flush(output), '完了後の再描画で画像が送られること'
    assert_includes output.string, 'a=T'
  end

  def test_returning_to_a_decoded_image_reuses_the_cached_view
    native_or_skip
    screen, ui, handler, graphics = renderer_for('gradient.jpg')
    ui.draw_screen(screen)

    # 完了を待つ
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
    until ui.poll_image_preview
      flunk 'デコードが終わらない' if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      sleep 0.005
    end
    screen.clear
    ui.draw_screen(screen)
    assert graphics.flush(StringIO.new)

    # 別のファイルに移ってから戻る
    entries = handler.get_active_entries
    handler.select_index(entries.index { |e| e[:name] == 'notes.txt' })
    screen.clear
    ui.draw_screen(screen)
    graphics.flush(StringIO.new)

    handler.select_index(entries.index { |e| e[:name] == 'gradient.jpg' })
    screen.clear
    ui.draw_screen(screen)
    output = StringIO.new
    # デコードし直さず、即座に画像が送られること
    assert graphics.flush(output), '同じ画像へ戻ったときに再デコード待ちにならないこと'
    assert_includes output.string, 'a=T'
  end

  # === セキュリティ ===

  def test_null_byte_in_path_is_rejected
    native_or_skip
    assert_nil Rufio::NativeImage.decode("#{path('gradient.png')}\0.jpg", max_w: 8, max_h: 8)
  end

  def test_fifo_does_not_hang_and_fails_immediately
    native_or_skip
    skip 'POSIX のみ' unless File.respond_to?(:mkfifo)

    fifo = path('trap.png')
    File.mkfifo(fifo)
    job = settle(Rufio::NativeImage.decode(fifo, max_w: 8, max_h: 8), timeout: 1)

    assert job.failed?, '名前付きパイプ（FIFO）でハングせず失敗すること'
    job.close
  end

  def test_completed_native_job_is_closed_immediately_after_fetching_result
    native_or_skip
    view = settle_view(view_for('gradient.jpg', pixels: [8, 8]))

    refute_nil view.transfer
    assert_nil view.instance_variable_get(:@job), '結果を取り込んだらネイティブジョブを即解放すること'
    view.release
  end
end
