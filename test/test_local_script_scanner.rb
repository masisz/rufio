# frozen_string_literal: true

require 'minitest/autorun'
require 'fileutils'
require 'tmpdir'

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'rufio'

class TestLocalScriptScanner < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
  end

  # === スキャン機能のテスト ===

  def test_detects_shell_scripts
    create_script('build.sh', "#!/bin/bash\necho hello")

    scanner = Rufio::LocalScriptScanner.new(@tmpdir)
    scripts = scanner.available_scripts

    assert_equal 1, scripts.size
    assert_equal 'build.sh', scripts.first[:name]
    assert_equal File.join(@tmpdir, 'build.sh'), scripts.first[:path]
  end

  def test_detects_multiple_script_types
    create_script('build.sh', "#!/bin/bash\necho hello")
    create_script('test.rb', "#!/usr/bin/env ruby\nputs 'hello'")
    create_script('deploy.py', "#!/usr/bin/env python3\nprint('hello')")

    scanner = Rufio::LocalScriptScanner.new(@tmpdir)
    names = scanner.available_scripts.map { |s| s[:name] }.sort

    assert_equal %w[build.sh deploy.py test.rb], names
  end

  def test_ignores_non_script_files
    File.write(File.join(@tmpdir, 'README.md'), '# README')
    File.write(File.join(@tmpdir, 'data.txt'), 'some data')
    create_script('build.sh', "#!/bin/bash\necho hello")

    scanner = Rufio::LocalScriptScanner.new(@tmpdir)
    scripts = scanner.available_scripts

    assert_equal 1, scripts.size
    assert_equal 'build.sh', scripts.first[:name]
  end

  def test_ignores_hidden_files
    create_script('.hidden.sh', "#!/bin/bash\necho hidden")
    create_script('visible.sh', "#!/bin/bash\necho visible")

    scanner = Rufio::LocalScriptScanner.new(@tmpdir)
    names = scanner.available_scripts.map { |s| s[:name] }

    refute_includes names, '.hidden.sh'
    assert_includes names, 'visible.sh'
  end

  def test_ignores_subdirectory_scripts
    sub = File.join(@tmpdir, 'subdir')
    FileUtils.mkdir_p(sub)
    create_script_in(sub, 'nested.sh', "#!/bin/bash\necho nested")
    create_script('top.sh', "#!/bin/bash\necho top")

    scanner = Rufio::LocalScriptScanner.new(@tmpdir)
    names = scanner.available_scripts.map { |s| s[:name] }

    assert_includes names, 'top.sh'
    refute_includes names, 'nested.sh'
  end

  def test_empty_directory
    scanner = Rufio::LocalScriptScanner.new(@tmpdir)
    assert_empty scanner.available_scripts
  end

  def test_nonexistent_directory
    scanner = Rufio::LocalScriptScanner.new('/nonexistent/path/12345')
    assert_empty scanner.available_scripts
  end

  # === 検索機能のテスト ===

  def test_find_script_by_full_name
    create_script('build.sh', "#!/bin/bash\necho hello")

    scanner = Rufio::LocalScriptScanner.new(@tmpdir)
    script = scanner.find_script('build.sh')

    refute_nil script
    assert_equal 'build.sh', script[:name]
  end

  def test_find_script_by_name_without_extension
    create_script('build.sh', "#!/bin/bash\necho hello")

    scanner = Rufio::LocalScriptScanner.new(@tmpdir)
    script = scanner.find_script('build')

    refute_nil script
    assert_equal 'build.sh', script[:name]
  end

  def test_find_script_returns_nil_for_nonexistent
    scanner = Rufio::LocalScriptScanner.new(@tmpdir)
    assert_nil scanner.find_script('nonexistent')
  end

  # === 補完機能のテスト ===

  def test_complete_with_prefix
    create_script('build.sh', "#!/bin/bash")
    create_script('bundle.rb', "#!/usr/bin/env ruby")
    create_script('test.sh', "#!/bin/bash")

    scanner = Rufio::LocalScriptScanner.new(@tmpdir)
    completions = scanner.complete('bu')

    assert_includes completions, 'build.sh'
    assert_includes completions, 'bundle.rb'
    refute_includes completions, 'test.sh'
  end

  def test_complete_with_empty_prefix
    create_script('build.sh', "#!/bin/bash")
    create_script('test.sh', "#!/bin/bash")

    scanner = Rufio::LocalScriptScanner.new(@tmpdir)
    completions = scanner.complete('')

    assert_equal 2, completions.size
  end

  def test_complete_returns_sorted_results
    create_script('zebra.sh', "#!/bin/bash")
    create_script('alpha.sh', "#!/bin/bash")

    scanner = Rufio::LocalScriptScanner.new(@tmpdir)
    completions = scanner.complete('')

    assert_equal %w[alpha.sh zebra.sh], completions
  end

  # === キャッシュのテスト ===

  def test_cache_reused_for_same_directory
    create_script('build.sh', "#!/bin/bash")

    scanner = Rufio::LocalScriptScanner.new(@tmpdir)
    scripts1 = scanner.available_scripts
    scripts2 = scanner.available_scripts

    assert_equal scripts1.object_id, scripts2.object_id
  end

  def test_cache_invalidated_on_directory_change
    dir2 = Dir.mktmpdir
    create_script('build.sh', "#!/bin/bash")
    create_script_in(dir2, 'deploy.sh', "#!/bin/bash")

    scanner = Rufio::LocalScriptScanner.new(@tmpdir)
    scripts1 = scanner.available_scripts
    assert_equal 1, scripts1.size
    assert_equal 'build.sh', scripts1.first[:name]

    scanner.update_directory(dir2)
    scripts2 = scanner.available_scripts
    assert_equal 1, scripts2.size
    assert_equal 'deploy.sh', scripts2.first[:name]

    FileUtils.rm_rf(dir2)
  end

  def test_initialize_without_directory
    scanner = Rufio::LocalScriptScanner.new
    assert_empty scanner.available_scripts
  end

  private

  def create_script(name, content)
    create_script_in(@tmpdir, name, content)
  end

  def create_script_in(dir, name, content)
    path = File.join(dir, name)
    File.write(path, content)
    File.chmod(0755, path)
  end
end
