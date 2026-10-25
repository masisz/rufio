# frozen_string_literal: true

require_relative 'test_helper'
require 'minitest/autorun'
require 'shellwords'

class TestScriptFile < Minitest::Test
  def test_command_preserves_interpreters_quoting_and_shell_arguments
    interpreters = { '.sh' => nil, '.rb' => 'ruby', '.py' => 'python3', '.pl' => 'perl',
                     '.js' => 'node', '.ts' => 'ts-node', '.ps1' => 'pwsh', '' => nil }
    interpreters.each do |extension, interpreter|
      path = "/scripts with spaces/task#{extension}"
      expected = [interpreter, path.shellescape].compact.join(' ')
      assert_equal expected, Rufio::ScriptFile.command(path)
      assert_equal "#{expected} 'two words'", Rufio::ScriptFile.command(path, args: "'two words'")
      assert_equal expected, Rufio::ScriptFile.command(path, args: '')
    end
  end

  def test_exact_name_precedes_extension_fallback_and_fallback_has_stable_priority
    scripts = [{ name: 'task.rb' }, { name: 'task.sh' }, { name: 'task' }]
    assert_equal scripts.last, Rufio::ScriptFile.find(scripts, 'task')
    assert_equal scripts.first, Rufio::ScriptFile.find(scripts, 'task.rb')
    assert_equal scripts[1], Rufio::ScriptFile.find(scripts.take(2), 'task')
    assert_nil Rufio::ScriptFile.find(scripts, 'missing')
  end

  def test_scanners_keep_their_search_scope_and_executable_file_policy
    Dir.mktmpdir do |dir|
      nested = File.join(dir, 'nested')
      FileUtils.mkdir_p(nested)
      %w[.sh .rb .py .pl .js .ts .ps1].each { |ext| File.write(File.join(dir, "task#{ext.upcase}"), '') }
      File.write(File.join(nested, 'nested.rb'), '')
      File.write(File.join(dir, 'tool'), '')
      File.chmod(0755, File.join(dir, 'tool'))
      File.write(File.join(dir, 'ignored.txt'), '')
      config = File.join(dir, 'script_paths.yml')
      File.write(config, [dir].to_yaml)

      local = Rufio::LocalScriptScanner.new(dir).available_scripts.map { |script| script[:name] }
      runner = Rufio::ScriptRunner.new(script_paths: [dir]).available_scripts.map { |script| script[:name] }
      manager = Rufio::ScriptPathManager.new(config).all_scripts
      assert_equal 7, local.length
      refute_includes local, 'nested.rb'
      refute_includes local, 'tool'
      assert_includes runner, 'nested.rb'
      assert_includes runner, 'tool'
      refute_includes runner, 'ignored.txt'
      assert_includes manager, 'nested'
      assert_includes manager, 'tool'
    end
  end

  def test_runner_can_execute_an_already_discovered_script_with_environment_and_arguments
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'task.rb')
      File.write(path, 'puts ARGV; puts ENV.fetch("RUFIO_CURRENT_DIR"); warn "warning"; exit 7')
      runner = Rufio::ScriptRunner.new(script_paths: [])
      result = runner.execute({ name: 'task.rb', path: path }, working_dir: dir, args: "'two words'")
      refute result[:success]
      assert_equal 7, result[:exit_code]
      assert_equal "two words\n#{dir}\n", result[:output]
      assert_equal "warning\n", result[:error]
    end
  end

  def test_path_manager_keeps_first_path_priority_and_reports_all_matches
    Dir.mktmpdir do |dir|
      paths = %w[first second].map { |name| File.join(dir, name) }
      paths.each do |path|
        FileUtils.mkdir_p(path)
        File.write(File.join(path, 'task.rb'), '')
      end
      config = File.join(dir, 'script_paths.yml')
      File.write(config, paths.to_yaml)
      manager = Rufio::ScriptPathManager.new(config)
      assert_equal File.join(paths.first, 'task.rb'), manager.resolve('TASK')
      assert_equal paths.map { |path| File.join(path, 'task.rb') }, manager.find_all_matches('TASK')
    end
  end
end
