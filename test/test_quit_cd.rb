# frozen_string_literal: true

require_relative 'test_helper'
require 'minitest/autorun'
require 'tmpdir'
require 'rbconfig'
require 'timeout'

# T キー: 確認なしで終了し、シェル関数（rufio --shell-init）が移動する先を --choosedir に書く
class TestQuitCd < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir('rufio_quit_cd')
    @target = File.join(@tmpdir, 'target')
    Dir.mkdir(@target)
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
  end

  def test_default_keybind_is_capital_t
    assert_equal 'T', Rufio::ConfigLoader.default_keybinds[:quit_cd]
  end

  def test_t_key_requests_quit_without_confirmation
    handler = keybind_handler
    STDIN.stub(:getch, -> { flunk 'T must not show a confirmation dialog' }) do
      assert_equal :quit_cd, handler.handle_key('T')
    end
  end

  def test_t_key_is_ignored_in_help_mode
    handler = keybind_handler
    handler.instance_variable_set(:@in_help_mode, true)
    assert_equal false, handler.handle_key('T')
  end

  def test_terminal_ui_stops_and_remembers_current_directory
    ui = Rufio::TerminalUI.new(test_mode: true)
    handler = keybind_handler
    ui.instance_variable_set(:@keybind_handler, handler)
    ui.instance_variable_set(:@directory_listing, handler.instance_variable_get(:@directory_listing))
    ui.instance_variable_set(:@running, true)
    # Windows の入力キュー経由で T を 1 キー渡す
    queue = Queue.new
    queue << 'T'.ord
    ui.instance_variable_set(:@input_queue, queue)
    ui.define_singleton_method(:windows?) { true }

    ui.send(:handle_input_nonblocking)

    refute ui.instance_variable_get(:@running)
    assert_equal @target, ui.exit_directory
  end

  def test_terminal_ui_has_no_exit_directory_by_default
    assert_nil Rufio::TerminalUI.new(test_mode: true).exit_directory
  end

  def test_application_writes_directory_to_choosedir
    choosedir = File.join(@tmpdir, 'cwd')
    app = Rufio::Application.new(@tmpdir, choosedir: choosedir)
    app.send(:write_choosedir, @target)
    assert_equal @target, File.read(choosedir)
  end

  # q などで終了した場合は何も書かず、シェルは移動しない
  def test_application_writes_nothing_without_exit_directory
    choosedir = File.join(@tmpdir, 'cwd')
    app = Rufio::Application.new(@tmpdir, choosedir: choosedir)
    app.send(:write_choosedir, nil)
    refute File.exist?(choosedir)
  end

  def test_application_writes_nothing_without_choosedir
    app = Rufio::Application.new(@tmpdir)
    app.send(:write_choosedir, @target)
    assert_empty Dir.children(@tmpdir) - ['target']
  end

  # 実際の rufio を疑似端末で起動し、rf 関数 → T → シェルの移動までを確認する
  def test_rf_function_moves_shell_after_t_key
    skip 'PTY と bash が必要' unless pty_available? && system('command -v bash > /dev/null 2>&1')

    pwd = run_rf_in_bash('T')
    assert_equal File.realpath(@target), File.realpath(pwd)
  end

  def test_rf_function_stays_after_q_quit
    skip 'PTY と bash が必要' unless pty_available? && system('command -v bash > /dev/null 2>&1')

    pwd = run_rf_in_bash('qy')
    assert_equal File.realpath(@tmpdir), File.realpath(pwd)
  end

  private

  def keybind_handler
    handler = Rufio::KeybindHandler.new
    handler.set_directory_listing(Rufio::DirectoryListing.new(@target))
    handler
  end

  def pty_available?
    require 'pty'
    true
  rescue LoadError
    false
  end

  def run_rf_in_bash(keys)
    bin_dir = File.join(@tmpdir, 'bin')
    Dir.mkdir(bin_dir)
    rufio = File.join(bin_dir, 'rufio')
    File.write(rufio, <<~SH)
      #!/bin/sh
      exec '#{RbConfig.ruby}' '#{File.expand_path('../bin/rufio', __dir__)}' "$@"
    SH
    File.chmod(0o755, rufio)
    pwd_file = File.join(@tmpdir, 'pwd')
    init = IO.popen([RbConfig.ruby, File.expand_path('../bin/rufio', __dir__), '--shell-init', 'bash'], &:read)
    init_file = File.join(@tmpdir, 'init.bash')
    File.write(init_file, init)
    command = "source '#{init_file}'; cd '#{@tmpdir}'; rf '#{@target}'; pwd > '#{pwd_file}'"
    env = { 'PATH' => "#{bin_dir}:#{ENV['PATH']}", 'HOME' => @tmpdir }

    PTY.spawn(env, 'bash', '--noprofile', '--norc', '-c', command) do |r, w, pid|
      reader = Thread.new do
        loop { r.readpartial(4096) }
      rescue Errno::EIO, EOFError, IOError
        nil
      end
      sleep 2 # rufio の起動を待つ
      keys.each_char do |key|
        w.write(key)
        sleep 0.5
      end
      Timeout.timeout(15) { Process.wait(pid) }
      reader.kill
    end
    File.read(pwd_file).strip
  end
end
