# frozen_string_literal: true

require_relative 'test_helper'
require 'minitest/autorun'
require 'timeout'
require 'tmpdir'
require 'fileutils'
require_relative '../lib/rufio'

# 検索は `/` 一本に統合した（G モード・`s`・`F` は廃止）。
# Files モードの `/` は旧 G モードの検索画面を、カレントディレクトリ配下だけを対象に開く。
class TestSearchMode < Minitest::Test
  # TerminalUI の代役（KeybindHandler から呼ばれた引数だけを記録する）
  class FakeTerminalUI
    attr_reader :roots

    def start_search(roots)
      @roots = roots
      true
    end

    # 呼ばれても落ちないようにする（検索以外の経路は検証しない）
    def respond_to_missing?(_name, _include_private = false)
      true
    end

    def method_missing(_name, *_args)
      nil
    end
  end

  def setup
    @dir = Dir.mktmpdir('rufio_search_mode')
    @sub = File.join(@dir, 'sub')
    FileUtils.mkdir_p(@sub)
    File.write(File.join(@dir, 'report.txt'), "alpha\nbeta\n")
    File.write(File.join(@sub, 'notes.md'), 'gamma')
    # ブックマークに入っていても検索されないことを確かめるための別ディレクトリ
    @outside = Dir.mktmpdir('rufio_search_outside')
    File.write(File.join(@outside, 'report_outside.txt'), 'alpha')
  end

  def teardown
    FileUtils.rm_rf(@dir) if @dir
    FileUtils.rm_rf(@outside) if @outside
  end

  # === キーバインド ===

  def test_slash_is_the_search_key
    assert_equal '/', Rufio::ConfigLoader.default_keybinds[:search]
  end

  def test_the_old_search_keys_are_gone
    keys = Rufio::ConfigLoader.default_keybinds
    %i[file_search file_search_alt rga_search global_search].each do |action|
      refute keys.key?(action), "#{action} は廃止したこと"
    end
    refute_includes keys.values, 's', 's は検索キーではなくなったこと'
    refute_includes keys.values, 'F', 'F（rga）は廃止したこと'
    refute_includes keys.values, 'G', 'G（G モード）は廃止したこと'
  end

  def test_a_legacy_keybind_setting_moves_to_search
    Rufio::ConfigLoader.stub(:load_config, { keybinds: { file_search: 's' } }) do
      assert_equal 's', Rufio::ConfigLoader.keybinds[:search],
                   '旧 file_search の設定は / の検索に引き継ぐこと'
    end
  end

  def test_modes_no_longer_include_the_search_tab
    refute_includes Rufio::TabModeManager::MODES, :global
    refute_includes Rufio::TabModeManager::MODE_KEYS.values, 'G'
  end

  def test_the_removed_search_screens_are_gone
    %i[FuzzyFinder SearchController RgaResultSource FuzzyCandidateCache FuzzyPreviewLoader].each do |name|
      refute Rufio.const_defined?(name), "Rufio::#{name} は廃止したこと"
    end
  end

  # === Files モードの / ===

  def handler_for(dir)
    handler = Rufio::KeybindHandler.new
    handler.set_directory_listing(Rufio::DirectoryListing.new(dir))
    @fake = FakeTerminalUI.new
    handler.set_terminal_ui(@fake)
    handler
  end

  def test_slash_opens_the_search_screen_rooted_at_the_current_directory
    handler = handler_for(@dir)

    assert handler.handle_key('/')
    assert_equal [@dir], @fake.roots.map { |root| root[:path] },
                 'カレントディレクトリだけを検索対象にすること'
  end

  def test_the_old_search_keys_do_nothing
    handler = handler_for(@dir)

    refute handler.handle_key('s')
    refute handler.handle_key('F')
    refute handler.handle_key('G')
    assert_nil @fake.roots
  end

  # === 検索画面（旧 G モード） ===

  def search_for(root)
    screen = Rufio::SearchScreen.new
    screen.open([{ name: File.basename(root), path: root }])
    settle(screen)
    screen
  end

  def settle(screen)
    Timeout.timeout(5) do
      while screen.scanning?
        screen.poll
        Thread.pass
      end
    end
  end

  def draw_text(screen, width: 80, height: 20)
    buffer = Rufio::Screen.new(width, height)
    screen.draw(buffer)
    (0...height).map { |y| buffer.row(y).to_s.gsub(/\e\[[0-9;]*m/, '') }.join("\n")
  end

  def test_the_search_screen_scans_only_the_given_root
    screen = search_for(@dir)
    screen.handle_key('report')
    settle(screen)

    paths = screen.results.map { |result| result[:path] }
    assert_includes paths, File.join(@dir, 'report.txt')
    refute(paths.any? { |path| path.start_with?(@outside) }, 'ブックマークは検索しないこと')
  ensure
    screen&.close
  end

  def test_the_search_screen_still_finds_files_in_subdirectories
    screen = search_for(@dir)
    screen.handle_key('notes')
    settle(screen)

    assert_equal [File.join(@sub, 'notes.md')], screen.results.map { |result| result[:path] }
  ensure
    screen&.close
  end

  def test_the_search_screen_still_searches_contents_with_tab
    screen = search_for(@dir)
    screen.handle_key("\t")
    screen.handle_key('beta')
    settle(screen)

    assert_equal [File.join(@dir, 'report.txt')], screen.results.map { |result| result[:path] }
  ensure
    screen&.close
  end

  def test_the_header_names_the_searched_directory_instead_of_g_mode
    screen = search_for(@dir)
    text = draw_text(screen)

    refute_includes text, 'G mode', 'G モードの名前は残さないこと'
    assert_includes text, 'Search'
    assert_includes text, File.basename(@dir)
  ensure
    screen&.close
  end

  def test_a_single_root_does_not_prefix_every_result
    screen = search_for(@dir)
    screen.handle_key('report')
    settle(screen)
    line = draw_text(screen).lines.find { |text| text.include?('report.txt') }

    refute_nil line
    refute_includes line, "[#{File.basename(@dir)}]",
                    '1 つのディレクトリだけを検索するときは行頭に名前を出さないこと'
  ensure
    screen&.close
  end
end
