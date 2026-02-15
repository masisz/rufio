# frozen_string_literal: true

require 'minitest/autorun'
require 'fileutils'
require 'tmpdir'

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'rufio'

class TestRakefileParser < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
  end

  # === Rakefile検出のテスト ===

  def test_detects_rakefile
    File.write(File.join(@tmpdir, 'Rakefile'), "task :test do\nend")

    parser = Rufio::RakefileParser.new(@tmpdir)
    assert parser.rakefile_exists?
  end

  def test_detects_lowercase_rakefile
    File.write(File.join(@tmpdir, 'rakefile'), "task :test do\nend")

    parser = Rufio::RakefileParser.new(@tmpdir)
    assert parser.rakefile_exists?
  end

  def test_detects_rakefile_rb
    File.write(File.join(@tmpdir, 'Rakefile.rb'), "task :test do\nend")

    parser = Rufio::RakefileParser.new(@tmpdir)
    assert parser.rakefile_exists?
  end

  def test_no_rakefile
    parser = Rufio::RakefileParser.new(@tmpdir)
    refute parser.rakefile_exists?
  end

  # === タスクパースのテスト ===

  def test_parse_symbol_task
    write_rakefile("task :test do\n  puts 'test'\nend")

    parser = Rufio::RakefileParser.new(@tmpdir)
    assert_includes parser.tasks, 'test'
  end

  def test_parse_string_task
    write_rakefile("task 'build' do\n  puts 'build'\nend")

    parser = Rufio::RakefileParser.new(@tmpdir)
    assert_includes parser.tasks, 'build'
  end

  def test_parse_double_quoted_task
    write_rakefile("task \"deploy\" do\n  puts 'deploy'\nend")

    parser = Rufio::RakefileParser.new(@tmpdir)
    assert_includes parser.tasks, 'deploy'
  end

  def test_parse_multiple_tasks
    content = <<~RUBY
      task :test do
        puts 'test'
      end

      task :build do
        puts 'build'
      end

      task :deploy do
        puts 'deploy'
      end
    RUBY
    write_rakefile(content)

    parser = Rufio::RakefileParser.new(@tmpdir)
    tasks = parser.tasks

    assert_includes tasks, 'test'
    assert_includes tasks, 'build'
    assert_includes tasks, 'deploy'
  end

  def test_parse_task_with_dependencies
    write_rakefile("task test: :build do\n  puts 'test'\nend")

    parser = Rufio::RakefileParser.new(@tmpdir)
    assert_includes parser.tasks, 'test'
  end

  def test_parse_task_with_arrow_dependencies
    write_rakefile("task :test => :build do\n  puts 'test'\nend")

    parser = Rufio::RakefileParser.new(@tmpdir)
    assert_includes parser.tasks, 'test'
  end

  def test_parse_default_task
    write_rakefile("task :default => :test")

    parser = Rufio::RakefileParser.new(@tmpdir)
    assert_includes parser.tasks, 'default'
  end

  def test_returns_sorted_unique_tasks
    content = <<~RUBY
      task :zebra do; end
      task :alpha do; end
      task :middle do; end
    RUBY
    write_rakefile(content)

    parser = Rufio::RakefileParser.new(@tmpdir)
    tasks = parser.tasks

    assert_equal tasks, tasks.sort
    assert_equal tasks, tasks.uniq
  end

  def test_empty_rakefile
    write_rakefile("")

    parser = Rufio::RakefileParser.new(@tmpdir)
    assert_empty parser.tasks
  end

  def test_no_rakefile_returns_empty
    parser = Rufio::RakefileParser.new(@tmpdir)
    assert_empty parser.tasks
  end

  def test_nonexistent_directory
    parser = Rufio::RakefileParser.new('/nonexistent/path/12345')
    assert_empty parser.tasks
    refute parser.rakefile_exists?
  end

  # === 補完のテスト ===

  def test_complete_with_prefix
    content = <<~RUBY
      task :test do; end
      task :test_unit do; end
      task :build do; end
    RUBY
    write_rakefile(content)

    parser = Rufio::RakefileParser.new(@tmpdir)
    completions = parser.complete('te')

    assert_includes completions, 'test'
    assert_includes completions, 'test_unit'
    refute_includes completions, 'build'
  end

  def test_complete_with_empty_prefix
    content = <<~RUBY
      task :test do; end
      task :build do; end
    RUBY
    write_rakefile(content)

    parser = Rufio::RakefileParser.new(@tmpdir)
    completions = parser.complete('')

    assert_equal 2, completions.size
  end

  # === キャッシュのテスト ===

  def test_cache_invalidated_on_directory_change
    dir2 = Dir.mktmpdir
    write_rakefile("task :test do; end")
    File.write(File.join(dir2, 'Rakefile'), "task :deploy do; end")

    parser = Rufio::RakefileParser.new(@tmpdir)
    assert_includes parser.tasks, 'test'

    parser.update_directory(dir2)
    tasks = parser.tasks
    assert_includes tasks, 'deploy'
    refute_includes tasks, 'test'

    FileUtils.rm_rf(dir2)
  end

  def test_initialize_without_directory
    parser = Rufio::RakefileParser.new
    assert_empty parser.tasks
    refute parser.rakefile_exists?
  end

  private

  def write_rakefile(content)
    File.write(File.join(@tmpdir, 'Rakefile'), content)
  end
end
