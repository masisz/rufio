# frozen_string_literal: true

require_relative 'test_helper'
require 'minitest/autorun'
require 'tmpdir'
require 'rbconfig'

class TestShellInit < Minitest::Test
  RUFIO_BIN = File.expand_path('../bin/rufio', __dir__)

  def setup
    @tmpdir = Dir.mktmpdir('rufio_shell_init')
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
  end

  # === シェルの判定 ===

  def test_detects_powershell_on_windows
    assert_equal 'powershell', Rufio::ShellInit.detect(platform: 'x64-mingw-ucrt', env: {})
    assert_equal 'powershell', Rufio::ShellInit.detect(platform: 'x64-mswin64_140', env: {})
  end

  def test_detects_login_shell_on_unix
    assert_equal 'zsh', Rufio::ShellInit.detect(platform: 'arm64-darwin23', env: { 'SHELL' => '/bin/zsh' })
    assert_equal 'fish', Rufio::ShellInit.detect(platform: 'x86_64-linux', env: { 'SHELL' => '/usr/bin/fish' })
    assert_equal 'bash', Rufio::ShellInit.detect(platform: 'x86_64-linux', env: { 'SHELL' => '/bin/bash' })
  end

  def test_falls_back_to_bash_on_unix_for_unknown_shell
    assert_equal 'bash', Rufio::ShellInit.detect(platform: 'x86_64-linux', env: { 'SHELL' => '/bin/tcsh' })
    assert_equal 'bash', Rufio::ShellInit.detect(platform: 'x86_64-linux', env: {})
  end

  # Git Bash など Windows 上の bash では bash 用の関数を出す
  def test_detects_bash_on_windows_when_shell_is_set
    assert_equal 'bash', Rufio::ShellInit.detect(platform: 'x64-mingw-ucrt', env: { 'SHELL' => '/usr/bin/bash' })
    assert_equal 'bash', Rufio::ShellInit.detect(platform: 'x64-mingw-ucrt', env: { 'SHELL' => 'C:\\Program Files\\Git\\usr\\bin\\bash.exe' })
  end

  # === 出力する関数 ===

  def test_scripts_define_rf_and_pass_choosedir
    assert_match(/^rf\(\) \{/, Rufio::ShellInit.script('bash'))
    assert_match(/^rf\(\) \{/, Rufio::ShellInit.script('zsh'))
    assert_match(/^function rf$/, Rufio::ShellInit.script('fish'))
    assert_match(/^function rf \{/, Rufio::ShellInit.script('powershell'))
    %w[bash zsh fish powershell].each do |shell|
      assert_includes Rufio::ShellInit.script(shell), '--choosedir', shell
    end
  end

  def test_pwsh_is_alias_of_powershell
    assert_equal Rufio::ShellInit.script('powershell'), Rufio::ShellInit.script('pwsh')
  end

  def test_rejects_unknown_shell
    assert_raises(ArgumentError) { Rufio::ShellInit.script('tcsh') }
  end

  def test_cli_prints_script_for_given_shell
    output = IO.popen([RbConfig.ruby, RUFIO_BIN, '--shell-init', 'fish'], &:read)
    assert_equal Rufio::ShellInit.script('fish'), output
    output = IO.popen([RbConfig.ruby, RUFIO_BIN, '--shell-init=powershell'], &:read)
    assert_equal Rufio::ShellInit.script('powershell'), output
  end

  def test_cli_rejects_unknown_shell
    IO.popen([RbConfig.ruby, RUFIO_BIN, '--shell-init=tcsh', err: File::NULL], &:read)
    refute $?.success?
  end

  # === 関数の動作（rufio の代わりに --choosedir へ書くだけのスタブを使う） ===

  def test_bash_function_changes_directory_written_by_rufio
    skip 'bash が必要' unless command?('bash')

    target = File.join(@tmpdir, 'dir with space')
    Dir.mkdir(target)
    pwd = run_shell('bash', Rufio::ShellInit.script('bash'), target)
    assert_equal File.realpath(target), File.realpath(pwd)
  end

  def test_bash_function_stays_when_rufio_writes_nothing
    skip 'bash が必要' unless command?('bash')

    pwd = run_shell('bash', Rufio::ShellInit.script('bash'), nil)
    assert_equal File.realpath(@tmpdir), File.realpath(pwd)
  end

  def test_zsh_function_changes_directory_written_by_rufio
    skip 'zsh が必要' unless command?('zsh')

    target = File.join(@tmpdir, 'target')
    Dir.mkdir(target)
    pwd = run_shell('zsh', Rufio::ShellInit.script('zsh'), target)
    assert_equal File.realpath(target), File.realpath(pwd)
  end

  def test_fish_function_changes_directory_written_by_rufio
    skip 'fish が必要' unless command?('fish')

    target = File.join(@tmpdir, 'target')
    Dir.mkdir(target)
    pwd = run_shell('fish', Rufio::ShellInit.script('fish'), target)
    assert_equal File.realpath(target), File.realpath(pwd)
  end

  def test_powershell_function_changes_directory_written_by_rufio
    shell = %w[pwsh powershell].find { |name| command?(name) }
    skip 'PowerShell が必要' unless shell

    target = File.join(@tmpdir, 'target')
    Dir.mkdir(target)
    script_path = File.join(@tmpdir, 'test.ps1')
    # PowerShell は関数を外部コマンドより優先するので、rufio を関数でスタブする
    File.write(script_path, <<~PS1)
      function rufio {
          if ($args[0] -ne '--choosedir') { exit 1 }
          Set-Content -LiteralPath $args[1] -Value '#{target}' -NoNewline -Encoding UTF8
      }
      Set-Location -LiteralPath '#{@tmpdir}'
      #{Rufio::ShellInit.script('powershell')}
      rf
      (Get-Location).Path
    PS1
    output = IO.popen([shell, '-NoProfile', '-NonInteractive', '-File', script_path], &:read)
    assert_equal File.realpath(target), File.realpath(output.lines.last.strip)
  end

  private

  def command?(name)
    ENV['PATH'].to_s.split(File::PATH_SEPARATOR).any? do |dir|
      ['', '.exe'].any? { |ext| File.executable?(File.join(dir, name + ext)) }
    end
  end

  # PATH 上の rufio を、--choosedir のファイルに target を書くだけのスタブにする
  def write_rufio_stub(dir, target)
    stub = File.join(dir, 'rufio')
    File.write(stub, <<~SH)
      #!/bin/sh
      [ "$1" = "--choosedir" ] || exit 1
      #{target ? "printf '%s' '#{target}' > \"$2\"" : ':'}
    SH
    File.chmod(0o755, stub)
  end

  def run_shell(shell, script, target)
    stub_dir = File.join(@tmpdir, 'bin')
    FileUtils.mkdir_p(stub_dir)
    write_rufio_stub(stub_dir, target)
    script_path = File.join(@tmpdir, "init.#{shell}")
    File.write(script_path, script)
    command = "source '#{script_path}'; cd '#{@tmpdir}'; rf; pwd"
    env = { 'PATH' => "#{stub_dir}#{File::PATH_SEPARATOR}#{ENV['PATH']}" }
    args = shell == 'fish' ? [shell, '--no-config', '-c', command] : [shell, '-c', command]
    output = IO.popen(env, args, &:read)
    assert $?.success?, "#{shell} の実行に失敗: #{output}"
    output.lines.last.strip
  end
end
