# frozen_string_literal: true

require_relative 'test_helper'
require_relative '../lib/rufio/file_operations'

class TestFileOperationsUnit < Minitest::Test
  def setup
    @operations = Rufio::FileOperations.new
    @test_dir = Dir.mktmpdir('rufio_test')
    @dest_dir = Dir.mktmpdir('rufio_dest')
  end

  def teardown
    FileUtils.rm_rf(@test_dir) if @test_dir && Dir.exist?(@test_dir)
    FileUtils.rm_rf(@dest_dir) if @dest_dir && Dir.exist?(@dest_dir)
  end

  # Move operation tests

  def test_move_single_file
    # Create test file
    test_file = File.join(@test_dir, 'test.txt')
    File.write(test_file, 'test content')

    result = @operations.move(['test.txt'], @test_dir, @dest_dir)

    assert result.success
    assert_equal 1, result.count
    refute File.exist?(test_file)
    assert File.exist?(File.join(@dest_dir, 'test.txt'))
  end

  def test_move_multiple_files
    # Create test files
    file1 = File.join(@test_dir, 'file1.txt')
    file2 = File.join(@test_dir, 'file2.txt')
    File.write(file1, 'content1')
    File.write(file2, 'content2')

    result = @operations.move(['file1.txt', 'file2.txt'], @test_dir, @dest_dir)

    assert result.success
    assert_equal 2, result.count
    assert File.exist?(File.join(@dest_dir, 'file1.txt'))
    assert File.exist?(File.join(@dest_dir, 'file2.txt'))
  end

  def test_move_directory
    # Create test directory
    test_subdir = File.join(@test_dir, 'subdir')
    Dir.mkdir(test_subdir)
    File.write(File.join(test_subdir, 'file.txt'), 'content')

    result = @operations.move(['subdir'], @test_dir, @dest_dir)

    assert result.success
    assert_equal 1, result.count
    refute Dir.exist?(test_subdir)
    assert Dir.exist?(File.join(@dest_dir, 'subdir'))
  end

  def test_move_file_already_exists_in_destination
    # Create same file in both directories
    test_file = File.join(@test_dir, 'test.txt')
    dest_file = File.join(@dest_dir, 'test.txt')
    File.write(test_file, 'test content')
    File.write(dest_file, 'existing content')

    result = @operations.move(['test.txt'], @test_dir, @dest_dir)

    refute result.success
    assert_equal 0, result.count
    assert result.errors.any? { |e| e.include?('Already exists') }
    # Original file should still exist
    assert File.exist?(test_file)
  end

  # Copy operation tests

  def test_copy_single_file
    # Create test file
    test_file = File.join(@test_dir, 'test.txt')
    File.write(test_file, 'test content')

    result = @operations.copy(['test.txt'], @test_dir, @dest_dir)

    assert result.success
    assert_equal 1, result.count
    # Original should still exist
    assert File.exist?(test_file)
    assert File.exist?(File.join(@dest_dir, 'test.txt'))
  end

  def test_copy_directory
    # Create test directory
    test_subdir = File.join(@test_dir, 'subdir')
    Dir.mkdir(test_subdir)
    File.write(File.join(test_subdir, 'file.txt'), 'content')

    result = @operations.copy(['subdir'], @test_dir, @dest_dir)

    assert result.success
    assert_equal 1, result.count
    # Original should still exist
    assert Dir.exist?(test_subdir)
    assert Dir.exist?(File.join(@dest_dir, 'subdir'))
    assert File.exist?(File.join(@dest_dir, 'subdir', 'file.txt'))
  end

  def test_copy_file_already_exists_in_destination
    # Create same file in both directories
    test_file = File.join(@test_dir, 'test.txt')
    dest_file = File.join(@dest_dir, 'test.txt')
    File.write(test_file, 'test content')
    File.write(dest_file, 'existing content')

    result = @operations.copy(['test.txt'], @test_dir, @dest_dir)

    refute result.success
    assert_equal 0, result.count
    assert result.errors.any? { |e| e.include?('Already exists') }
  end

  # Delete operation tests

  def test_delete_single_file
    # Create test file
    test_file = File.join(@test_dir, 'test.txt')
    File.write(test_file, 'test content')

    result = @operations.delete(['test.txt'], @test_dir)

    assert result.success
    assert_equal 1, result.count
    refute File.exist?(test_file)
  end

  def test_delete_multiple_files
    # Create test files
    file1 = File.join(@test_dir, 'file1.txt')
    file2 = File.join(@test_dir, 'file2.txt')
    File.write(file1, 'content1')
    File.write(file2, 'content2')

    result = @operations.delete(['file1.txt', 'file2.txt'], @test_dir)

    assert result.success
    assert_equal 2, result.count
    refute File.exist?(file1)
    refute File.exist?(file2)
  end

  def test_delete_directory
    # Create test directory
    test_subdir = File.join(@test_dir, 'subdir')
    Dir.mkdir(test_subdir)
    File.write(File.join(test_subdir, 'file.txt'), 'content')

    result = @operations.delete(['subdir'], @test_dir)

    assert result.success
    assert_equal 1, result.count
    refute Dir.exist?(test_subdir)
  end

  def test_delete_nonexistent_file
    result = @operations.delete(['nonexistent.txt'], @test_dir)

    refute result.success
    assert_equal 0, result.count
    assert result.errors.any? { |e| e.include?('not found') }
  end

  # Create file tests

  def test_create_file
    result = @operations.create_file(@test_dir, 'newfile.txt')

    assert result.success
    assert_equal 1, result.count
    assert File.exist?(File.join(@test_dir, 'newfile.txt'))
  end

  def test_create_file_already_exists
    existing_file = File.join(@test_dir, 'existing.txt')
    File.write(existing_file, 'content')

    result = @operations.create_file(@test_dir, 'existing.txt')

    refute result.success
    assert_equal 0, result.count
    assert result.message.include?('already exists')
  end

  def test_create_file_invalid_name_with_slash
    result = @operations.create_file(@test_dir, 'invalid/name.txt')

    refute result.success
    assert_equal 0, result.count
    assert result.message.include?('Invalid filename')
  end

  def test_create_file_invalid_name_with_backslash
    result = @operations.create_file(@test_dir, 'invalid\\name.txt')

    refute result.success
    assert_equal 0, result.count
    assert result.message.include?('Invalid filename')
  end

  # Create directory tests

  def test_create_directory
    result = @operations.create_directory(@test_dir, 'newdir')

    assert result.success
    assert_equal 1, result.count
    assert Dir.exist?(File.join(@test_dir, 'newdir'))
  end

  def test_create_directory_already_exists
    existing_dir = File.join(@test_dir, 'existing')
    Dir.mkdir(existing_dir)

    result = @operations.create_directory(@test_dir, 'existing')

    refute result.success
    assert_equal 0, result.count
    assert result.message.include?('already exists')
  end

  def test_create_directory_invalid_name_with_slash
    result = @operations.create_directory(@test_dir, 'invalid/name')

    refute result.success
    assert_equal 0, result.count
    assert result.message.include?('Invalid directory name')
  end

  def test_create_directory_invalid_name_with_backslash
    result = @operations.create_directory(@test_dir, 'invalid\\name')

    refute result.success
    assert_equal 0, result.count
    assert result.message.include?('Invalid directory name')
  end

  # Mixed success/failure tests

  def test_move_mixed_success_failure
    # Create one file and don't create another
    file1 = File.join(@test_dir, 'file1.txt')
    File.write(file1, 'content1')

    result = @operations.move(['file1.txt', 'nonexistent.txt'], @test_dir, @dest_dir)

    refute result.success
    assert_equal 1, result.count
    assert_equal 1, result.errors.length
    assert File.exist?(File.join(@dest_dir, 'file1.txt'))
  end

  def test_operation_result_structure
    test_file = File.join(@test_dir, 'test.txt')
    File.write(test_file, 'test content')

    result = @operations.move(['test.txt'], @test_dir, @dest_dir)

    assert_respond_to result, :success
    assert_respond_to result, :message
    assert_respond_to result, :count
    assert_respond_to result, :errors

    assert_kind_of TrueClass, result.success
    assert_kind_of String, result.message
    assert_kind_of Integer, result.count
    assert_kind_of Array, result.errors
  end
end
