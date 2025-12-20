# frozen_string_literal: true

require_relative 'test_helper'
require_relative '../lib/rufio/logger'
require 'tempfile'

class TestLogger < Minitest::Test
  def setup
    @original_debug_env = ENV['BENIYA_DEBUG']
    @original_log_file = Rufio::Logger::LOG_FILE

    # Create a temporary log file for testing
    @temp_log_file = Tempfile.new(['rufio_test_log', '.log'])
    @temp_log_path = @temp_log_file.path
    @temp_log_file.close

    # Override LOG_FILE constant for testing (remove first to avoid warning)
    Rufio::Logger.send(:remove_const, :LOG_FILE) if Rufio::Logger.const_defined?(:LOG_FILE)
    Rufio::Logger.const_set(:LOG_FILE, @temp_log_path)
  end

  def teardown
    # Restore original environment and constant
    ENV['BENIYA_DEBUG'] = @original_debug_env

    # Restore original LOG_FILE constant
    Rufio::Logger.send(:remove_const, :LOG_FILE) if Rufio::Logger.const_defined?(:LOG_FILE)
    Rufio::Logger.const_set(:LOG_FILE, @original_log_file) if @original_log_file

    # Clean up temporary file
    File.delete(@temp_log_path) if File.exist?(@temp_log_path)
  end

  def test_debug_disabled_by_default
    ENV['BENIYA_DEBUG'] = nil

    Rufio::Logger.debug('Test message')

    # Log file should not be created when debug is disabled
    refute(File.exist?(@temp_log_path) && File.size(@temp_log_path) > 0,
           'Log file should not exist or be empty when debug is disabled')
  end

  def test_debug_logs_when_enabled
    ENV['BENIYA_DEBUG'] = '1'

    Rufio::Logger.debug('Test debug message')

    assert File.exist?(@temp_log_path)
    content = File.read(@temp_log_path)
    assert_includes content, 'DEBUG'
    assert_includes content, 'Test debug message'
  end

  def test_debug_with_context
    ENV['BENIYA_DEBUG'] = '1'

    Rufio::Logger.debug('Operation started', context: { file: 'test.txt', count: 5 })

    content = File.read(@temp_log_path)
    assert_includes content, 'Operation started'
    assert_includes content, 'Context:'
    assert_includes content, 'file:'
    assert_includes content, 'test.txt'
    assert_includes content, 'count:'
    assert_includes content, '5'
  end

  def test_info_logs_when_enabled
    ENV['BENIYA_DEBUG'] = '1'

    Rufio::Logger.info('Info message')

    content = File.read(@temp_log_path)
    assert_includes content, 'INFO'
    assert_includes content, 'Info message'
  end

  def test_warn_logs_when_enabled
    ENV['BENIYA_DEBUG'] = '1'

    Rufio::Logger.warn('Warning message')

    content = File.read(@temp_log_path)
    assert_includes content, 'WARN'
    assert_includes content, 'Warning message'
  end

  def test_error_logs_when_enabled
    ENV['BENIYA_DEBUG'] = '1'

    Rufio::Logger.error('Error occurred')

    content = File.read(@temp_log_path)
    assert_includes content, 'ERROR'
    assert_includes content, 'Error occurred'
  end

  def test_error_with_exception
    ENV['BENIYA_DEBUG'] = '1'

    begin
      raise StandardError, 'Test exception'
    rescue StandardError => e
      Rufio::Logger.error('Exception caught', exception: e)
    end

    content = File.read(@temp_log_path)
    assert_includes content, 'ERROR'
    assert_includes content, 'Exception caught'
    assert_includes content, 'exception:'
    assert_includes content, 'Test exception'
    assert_includes content, 'backtrace:'
  end

  def test_error_with_context_and_exception
    ENV['BENIYA_DEBUG'] = '1'

    begin
      raise StandardError, 'Test error'
    rescue StandardError => e
      Rufio::Logger.error('Operation failed', exception: e, context: { operation: 'delete', file: 'test.txt' })
    end

    content = File.read(@temp_log_path)
    assert_includes content, 'Operation failed'
    assert_includes content, 'exception:'
    assert_includes content, 'Test error'
    assert_includes content, 'operation:'
    assert_includes content, 'delete'
    assert_includes content, 'file:'
    assert_includes content, 'test.txt'
  end

  def test_clear_log
    ENV['BENIYA_DEBUG'] = '1'

    # Write some logs
    Rufio::Logger.debug('First message')
    Rufio::Logger.debug('Second message')

    # Clear the log
    Rufio::Logger.clear_log

    content = File.read(@temp_log_path)
    refute_includes content, 'First message'
    refute_includes content, 'Second message'
    assert_includes content, 'Rufio Debug Log Cleared'
  end

  def test_timestamp_format
    ENV['BENIYA_DEBUG'] = '1'

    Rufio::Logger.debug('Test timestamp')

    content = File.read(@temp_log_path)
    # Should match format like [2025-01-15 10:30:45]
    assert_match(/\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\]/, content)
  end

  def test_multiple_log_entries
    ENV['BENIYA_DEBUG'] = '1'

    Rufio::Logger.debug('First entry')
    Rufio::Logger.info('Second entry')
    Rufio::Logger.warn('Third entry')
    Rufio::Logger.error('Fourth entry')

    content = File.read(@temp_log_path)
    assert_includes content, 'DEBUG'
    assert_includes content, 'First entry'
    assert_includes content, 'INFO'
    assert_includes content, 'Second entry'
    assert_includes content, 'WARN'
    assert_includes content, 'Third entry'
    assert_includes content, 'ERROR'
    assert_includes content, 'Fourth entry'
  end

  def test_large_context_array_truncation
    ENV['BENIYA_DEBUG'] = '1'

    large_array = (1..20).to_a
    Rufio::Logger.debug('Large array test', context: { items: large_array })

    content = File.read(@temp_log_path)
    assert_includes content, 'items:'
    # Should indicate array size instead of printing all items
    assert_includes content, '[20 items]'
  end

  def test_log_file_append_mode
    ENV['BENIYA_DEBUG'] = '1'

    Rufio::Logger.debug('First log')
    first_content = File.read(@temp_log_path)

    Rufio::Logger.debug('Second log')
    second_content = File.read(@temp_log_path)

    # Both logs should be present
    assert_includes second_content, 'First log'
    assert_includes second_content, 'Second log'
    # Second content should be longer
    assert second_content.length > first_content.length
  end
end
