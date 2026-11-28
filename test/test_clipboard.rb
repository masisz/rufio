# frozen_string_literal: true

require_relative 'test_helper'
require 'minitest/autorun'
require 'stringio'
require 'fileutils'
require 'tmpdir'

# Clipboard: 手段の選択、シェルを経由しない実行、OSC 52 のフォールバック
class TestClipboard < Minitest::Test
  ENV_KEYS = %w[TMUX TERM DISPLAY WAYLAND_DISPLAY].freeze

  def setup
    @dir = Dir.mktmpdir('rufio_clipboard_test')
    @saved_env = ENV_KEYS.to_h { |key| [key, ENV[key]] }
    @saved_host_os = RbConfig::CONFIG['host_os']
    # macOS / Windows 環境で実クリップボード（pbcopy / clip）へ誤送信しないよう、既定は OS コマンド無しに揃える
    RbConfig::CONFIG['host_os'] = 'linux-gnu'
    ENV_KEYS.each { |key| ENV.delete(key) }
    Rufio::Clipboard.reset!
  end

  def teardown
    RbConfig::CONFIG['host_os'] = @saved_host_os
    @saved_env.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    Rufio::Clipboard.reset!
    FileUtils.rm_rf(@dir) if @dir && Dir.exist?(@dir)
  end

  def with_host_os(value)
    original = RbConfig::CONFIG['host_os']
    RbConfig::CONFIG['host_os'] = value
    Rufio::Clipboard.reset!
    yield
  ensure
    RbConfig::CONFIG['host_os'] = original
    Rufio::Clipboard.reset!
  end

  def with_clipboard_command(value)
    Rufio::ConfigLoader.stub(:clipboard_command, value) do
      Rufio::Clipboard.reset!
      yield
    end
  ensure
    Rufio::Clipboard.reset!
  end

  def candidate_names
    Rufio::Clipboard.send(:platform_candidates).map(&:name)
  end

  # === 手段の選択 ===

  def test_macos_uses_pbcopy
    with_host_os('darwin21') { assert_equal [:pbcopy], candidate_names }
  end

  def test_windows_tries_clip_then_powershell
    with_host_os('mingw32') { assert_equal %i[clip set_clipboard], candidate_names }
  end

  def test_linux_without_a_session_has_no_command
    with_host_os('linux-gnu') do
      assert_empty candidate_names, 'DISPLAY も WAYLAND_DISPLAY もなければ OSC 52 に任せる'
    end
  end

  def test_wayland_and_x11_candidates
    with_host_os('linux-gnu') do
      ENV['WAYLAND_DISPLAY'] = 'wayland-0'
      Rufio::Clipboard.reset!
      assert_equal [:wl_copy], candidate_names

      ENV['DISPLAY'] = ':0'
      Rufio::Clipboard.reset!
      assert_equal %i[wl_copy xclip xsel], candidate_names
    end
  end

  def test_x11_candidates_pass_the_clipboard_selection
    with_host_os('linux-gnu') do
      ENV['DISPLAY'] = ':0'
      Rufio::Clipboard.reset!
      argv = Rufio::Clipboard.send(:platform_candidates).find { |c| c.name == :xclip }.argv
      assert_equal %w[xclip -selection clipboard], argv
    end
  end

  # === 設定されたコマンド ===

  def test_configured_command_receives_the_text_on_stdin
    skip 'POSIX の実行可能スクリプトが必要' if windows_platform?

    output = File.join(@dir, 'clipboard.txt')
    script = File.join(@dir, 'fake-copy')
    File.write(script, "#!/bin/sh\ncat > #{output}\n")
    FileUtils.chmod(0o755, script)

    with_clipboard_command([script]) do
      assert_equal :configured, Rufio::Clipboard.copy('みかん,150')
      assert_equal 'みかん,150', File.read(output, encoding: 'UTF-8')
    end
  end

  def test_configured_command_is_not_run_through_a_shell
    marker = File.join(@dir, 'shell-ran')
    out = StringIO.new

    with_clipboard_command(["touch #{marker} || true"]) do
      # argv の 1 要素として扱われるため、コマンドとしては見つからず OSC 52 に落ちる
      assert_equal :osc52, Rufio::Clipboard.copy('text', out: out)
    end
    refute File.exist?(marker), 'シェルを経由しないこと'
  end

  def test_missing_configured_command_falls_back_to_osc52
    out = StringIO.new
    with_clipboard_command([File.join(@dir, 'does-not-exist')]) do
      assert_equal :osc52, Rufio::Clipboard.copy('text', out: out)
    end
  end

  def test_invalid_configured_values_are_ignored
    assert_nil Rufio::ConfigLoader.stub(:load_config, { clipboard_command: 42 }) {
      Rufio::ConfigLoader.clipboard_command
    }
    assert_nil Rufio::ConfigLoader.stub(:load_config, { clipboard_command: [] }) {
      Rufio::ConfigLoader.clipboard_command
    }
    assert_nil Rufio::ConfigLoader.stub(:load_config, { clipboard_command: [1, 2] }) {
      Rufio::ConfigLoader.clipboard_command
    }
    assert_equal 'pbcopy', Rufio::ConfigLoader.stub(:load_config, { clipboard_command: 'pbcopy' }) {
      Rufio::ConfigLoader.clipboard_command
    }
  end

  # === OSC 52 ===

  def test_osc52_writes_the_base64_payload
    out = StringIO.new
    assert_equal :osc52, Rufio::Clipboard.copy('みかん,150', out: out)

    assert_match(/\A\e\]52;c;[A-Za-z0-9+\/=]+\a\z/, out.string)
    payload = out.string[/;c;([^\a]+)/, 1]
    assert_equal 'みかん,150', Base64.strict_decode64(payload).force_encoding('UTF-8')
  end

  def test_osc52_is_wrapped_for_tmux
    ENV['TMUX'] = '/tmp/tmux-1000/default,1,0'
    ENV['TERM'] = 'screen-256color'
    out = StringIO.new
    Rufio::Clipboard.copy('cell', out: out)

    assert out.string.start_with?("\ePtmux;"), 'tmux では DCS パススルーで包むこと'
    assert out.string.end_with?("\e\\")
    assert_includes out.string, "\e\e]52;c;", 'ESC を二重にすること'
  end

  def test_osc52_is_wrapped_for_screen
    ENV['TERM'] = 'screen.xterm-256color'
    out = StringIO.new
    Rufio::Clipboard.copy('cell', out: out)

    assert out.string.start_with?("\eP")
    refute_includes out.string, 'tmux;'
    assert out.string.end_with?("\e\\")
  end

  def test_osc52_is_not_wrapped_in_a_plain_terminal
    ENV['TERM'] = 'xterm-256color'
    out = StringIO.new
    Rufio::Clipboard.copy('cell', out: out)

    assert out.string.start_with?("\e]52;c;")
  end

  def test_osc52_refuses_an_oversized_payload
    out = StringIO.new
    # base64 にすると 4/3 倍になるため、上限を超える長さを選ぶ
    text = 'x' * (Rufio::Clipboard::OSC52_MAX_BYTES * 3 / 4 + 100)
    refute Rufio::Clipboard.copy(text, out: out)
    assert_empty out.string
  end

  # === 貼り付け時の実行を防ぐ ===

  def test_trailing_newline_is_removed
    # 末尾の改行が残っていると、シェルに貼り付けた瞬間に実行される
    out = StringIO.new
    Rufio::Clipboard.copy("rm -rf ~/important\n", out: out)
    payload = Base64.strict_decode64(out.string[/;c;([^\a]+)/, 1])

    assert_equal 'rm -rf ~/important', payload.force_encoding('UTF-8')
  end

  def test_interior_newlines_are_kept
    out = StringIO.new
    Rufio::Clipboard.copy("first\nsecond\r\n", out: out)
    payload = Base64.strict_decode64(out.string[/;c;([^\a]+)/, 1]).force_encoding('UTF-8')

    assert_equal "first\nsecond", payload, 'セルの中身は保つが末尾だけ落とす'
  end

  def test_only_newlines_is_nothing_to_copy
    out = StringIO.new
    refute Rufio::Clipboard.copy("\n\n", out: out)
    assert_empty out.string
  end

  def test_control_characters_other_than_newline_are_replaced
    # 貼り付け先の端末を操作しうるため、ESC などは空白にする
    out = StringIO.new
    Rufio::Clipboard.copy("x\e]52;c;cHduZWQ=\ay", out: out)
    payload = Base64.strict_decode64(out.string[/;c;([^\a]+)/, 1]).force_encoding('UTF-8')

    refute_includes payload, "\e"
    refute_includes payload, "\a"
    assert_includes payload, 'x'
  end

  def test_tabs_are_kept
    out = StringIO.new
    Rufio::Clipboard.copy("a\tb", out: out)
    payload = Base64.strict_decode64(out.string[/;c;([^\a]+)/, 1]).force_encoding('UTF-8')

    assert_equal "a\tb", payload
  end

  # === 入力の検証 ===

  def test_nothing_is_copied_for_empty_input
    out = StringIO.new
    refute Rufio::Clipboard.copy(nil, out: out)
    refute Rufio::Clipboard.copy('', out: out)
    assert_empty out.string
  end

  def test_oversized_text_is_refused
    out = StringIO.new
    refute Rufio::Clipboard.copy('x' * (Rufio::Clipboard::MAX_BYTES + 1), out: out)
    assert_empty out.string
  end

  # === ヘルスチェック用 ===

  def test_available_method_reports_osc52_without_a_command
    with_host_os('linux-gnu') do
      assert_equal :osc52, Rufio::Clipboard.available_method
      assert_nil Rufio::Clipboard.available_command
    end
  end

  def test_available_command_reports_the_configured_command
    skip 'POSIX の実行可能スクリプトが必要' if windows_platform?

    script = File.join(@dir, 'fake-copy')
    File.write(script, "#!/bin/sh\ncat > /dev/null\n")
    FileUtils.chmod(0o755, script)

    with_clipboard_command([script]) do
      assert_equal :configured, Rufio::Clipboard.available_method
      assert_equal [script], Rufio::Clipboard.available_command
    end
  end
end
