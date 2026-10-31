# frozen_string_literal: true

# Windows キー入力の実機ログテスト（対話型）
#
# 実際にキーを押して、TerminalUI の入力スレッドに届いたバイトとその時刻、
# キー判定の結果をログファイルに書き出す。通常のテスト実行ではスキップする。
#
#   PowerShell: $env:RUFIO_INPUT_LOG=1; bundle exec ruby -Ilib -Itest test/test_windows_input_log.rb
#   cmd.exe:    set RUFIO_INPUT_LOG=1 && bundle exec ruby -Ilib -Itest test/test_windows_input_log.rb
#
# ログの保存先は RUFIO_INPUT_LOG_FILE（既定: ~/rufio_input_log.txt）。
# 各フェーズの制限時間は RUFIO_INPUT_LOG_SECONDS（既定: 30 秒）。

require_relative 'test_helper'
require 'minitest/autorun'

class TestWindowsInputLog < Minitest::Test
  ARROW_KEYS = %i[up down left right].freeze

  # 入力スレッドがキューに積んだバイトを時刻付きで記録する
  module LoggingQueue
    attr_accessor :input_log

    def push(byte, *args)
      input_log&.byte(byte)
      super
    end
    alias << push
  end

  class InputLog
    attr_reader :keys

    def initialize(path)
      @path = path
      @lines = []
      @keys = []
      @start = now
      @last_byte_at = nil
      @mutex = Mutex.new
    end

    def note(message)
      add(format('%10.3fms  %s', elapsed_ms, message))
    end

    def byte(value)
      at = now
      gap = @last_byte_at ? format(' (+%.3fms)', (at - @last_byte_at) * 1000) : ''
      @last_byte_at = at
      char = value.between?(0x20, 0x7E) ? " #{value.chr.inspect}" : ''
      add(format('%10.3fms  BYTE 0x%02X%s%s', (at - @start) * 1000, value, char, gap))
    end

    def key(value)
      @mutex.synchronize { @keys << value }
      note("KEY  #{value.inspect}")
    end

    def write
      File.write(@path, @lines.join("\n") + "\n")
    end

    private

    def add(line)
      @mutex.synchronize { @lines << line }
    end

    def now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def elapsed_ms
      (now - @start) * 1000
    end
  end

  def setup
    skip 'RUFIO_INPUT_LOG=1 のときだけ実行する対話型テスト' unless ENV['RUFIO_INPUT_LOG'] == '1'
    skip '端末から実行してください' unless STDIN.tty?

    @log_path = ENV['RUFIO_INPUT_LOG_FILE'] || File.join(Dir.home, 'rufio_input_log.txt')
    @seconds = (ENV['RUFIO_INPUT_LOG_SECONDS'] || 30).to_f
    @log = InputLog.new(@log_path)
    @ui = Rufio::TerminalUI.new(test_mode: true)
  end

  def teardown
    return unless @log

    @log.write
    puts "\n入力ログ: #{@log_path}"
  end

  # 実機での入力をまとめて確認する（G mode の矢印キー → 入力ダイアログ）
  def test_record_windows_key_input
    log_environment
    with_terminal do
      record_g_mode_keys
      record_input_dialog
    end

    keys = @log.keys
    misread = keys.each_cons(2).count { |a, b| a == "\e" && b == '[' }
    arrows = keys.count { |k| ARROW_KEYS.include?(k) }
    @log.note("SUMMARY arrows=#{arrows} misread_as_esc=#{misread}")

    assert_operator arrows, :>, 0, "G mode で矢印キーが 1 回も認識されなかった（ログ: #{@log_path}）"
    assert_equal 0, misread, "矢印キーが ESC + 文字として誤認された（ログ: #{@log_path}）"
    assert_equal 'rufio', @dialog_result, "入力ダイアログの結果が一致しない（ログ: #{@log_path}）"
  end

  private

  def with_terminal
    @ui.send(:setup_terminal)
    queue = @ui.instance_variable_get(:@input_queue)
    if queue
      queue.singleton_class.prepend(LoggingQueue)
      queue.input_log = @log
    else
      @log.note('NOTE input queue なし（Windows 以外）: バイト単位のログは取れない')
    end
    log_console_mode
    yield
  ensure
    @ui.send(:cleanup_terminal)
  end

  # G mode を実際に検索させた状態で、矢印キーの判定結果を記録する
  def record_g_mode_keys
    @log.note("PHASE g_mode read_next_input_byte timeout=#{@ui.send(:windows?) ? '0.1s' : 'n/a'}")
    global_search = @ui.instance_variable_get(:@global_search)
    global_search.open(bookmark_roots)
    log = @log
    done = false
    @ui.define_singleton_method(:handle_global_search_input) do |input|
      log.key(input)
      done = true if input == 'q'
      true
    end

    width = @ui.instance_variable_get(:@screen_width)
    height = @ui.instance_variable_get(:@screen_height)
    screen = Rufio::Screen.new(width, height)
    renderer = Rufio::Renderer.new(width, height)
    message = '[1/2] ↑↓←→ を10回ほど押し、ESC を1回押し、最後に q で次へ'
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + @seconds

    until done || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      Rufio::TerminalUI::MAX_INPUTS_PER_FRAME.times do
        break unless @ui.send(:handle_input_nonblocking)
        break if done
      end
      global_search.poll
      global_search.draw(screen)
      screen.put_string(0, height - 1, message, fg: "\e[1;33m")
      renderer.render(screen)
      sleep 0.008
    end
    @log.note("PHASE g_mode end (#{done ? 'q' : 'timeout'}) scanning=#{global_search.scanning?} results=#{global_search.results.length}")
    global_search.close
  end

  # ブックマーク名入力と同じダイアログで、1 回の入力で文字が入るかを記録する
  def record_input_dialog
    @log.note('PHASE input_dialog')
    print "\e[2J"
    @dialog_result = Rufio::DialogRenderer.new.show_input_dialog(
      '[2/2] Input test', 'Type rufio and press Enter'
    )
    @log.note("DIALOG result=#{@dialog_result.inspect}")
  end

  def bookmark_roots
    bookmarks = Rufio::BookmarkManager.new.list
    bookmarks.empty? ? [{ name: 'home', path: Dir.home }] : bookmarks
  rescue StandardError => e
    @log.note("NOTE bookmarks unavailable: #{e.message}")
    [{ name: 'home', path: Dir.home }]
  end

  def log_environment
    @log.note("RUBY #{RUBY_VERSION} #{RUBY_PLATFORM}")
    @log.note("io-console #{Gem.loaded_specs['io-console']&.version || 'default'}")
    @log.note("Queue#pop(timeout:) #{Rufio::KeyInput::QUEUE_POP_TIMEOUT_SUPPORTED}")
    %w[WT_SESSION TERM_PROGRAM TERM ConEmuANSI].each do |name|
      @log.note("ENV #{name}=#{ENV[name].inspect}")
    end
  end

  # raw モード後のコンソール入力モード（0x0200 = ENABLE_VIRTUAL_TERMINAL_INPUT）
  def log_console_mode
    return unless @ui.send(:windows?)

    require 'fiddle'
    kernel32 = Fiddle.dlopen('kernel32')
    get_std_handle = Fiddle::Function.new(kernel32['GetStdHandle'], [Fiddle::TYPE_LONG], Fiddle::TYPE_VOIDP)
    get_mode = Fiddle::Function.new(kernel32['GetConsoleMode'], [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT)
    mode = Fiddle::Pointer.malloc(4)
    get_mode.call(get_std_handle.call(-10), mode)
    @log.note(format('CONSOLE input mode=0x%04X', mode[0, 4].unpack1('L')))
  rescue StandardError => e
    @log.note("NOTE console mode unavailable: #{e.message}")
  end
end
