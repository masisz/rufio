# frozen_string_literal: true

require 'test_helper'

class TestMultilingualIntegration < Minitest::Test
  def setup
    Rufio::Config.reset_language!
  end

  def teardown
    Rufio::Config.reset_language!
  end

  def test_config_loader_returns_correct_messages
    # Test English (default)
    assert_equal 'rufio interrupted', Rufio::ConfigLoader.message('app.interrupted')
    
    # Test Japanese
    Rufio::Config.current_language = 'ja'
    assert_equal 'rufioを中断しました', Rufio::ConfigLoader.message('app.interrupted')
  end

  def test_health_checker_uses_config_messages
    health_checker = Rufio::HealthChecker.new
    
    # Capture output in English
    Rufio::Config.current_language = 'en'
    stdout_en, _stderr = capture_io do
      health_checker.run_check
    end
    
    assert stdout_en.include?('rufio Health Check')
    assert stdout_en.include?('Ruby version')
    
    # Capture output in Japanese
    Rufio::Config.current_language = 'ja'
    stdout_ja, _stderr = capture_io do
      health_checker.run_check
    end
    
    assert stdout_ja.include?('rufio ヘルスチェック')
    assert stdout_ja.include?('Ruby バージョン')
  end

  def test_file_preview_uses_config_messages
    file_preview = Rufio::FilePreview.new
    
    # Test with non-existent file
    Rufio::Config.current_language = 'en'
    result_en = file_preview.preview_file('/nonexistent/file.txt')
    assert_equal 'error', result_en[:type]
    assert result_en[:message].include?('File not found')
    
    # Test in Japanese
    Rufio::Config.current_language = 'ja'
    result_ja = file_preview.preview_file('/nonexistent/file.txt')
    assert_equal 'error', result_ja[:type]
    assert result_ja[:message].include?('ファイルが見つかりません')
  end

  def test_language_persistence_across_operations
    # Set language to Japanese
    Rufio::Config.current_language = 'ja'
    
    # Multiple operations should all use Japanese
    assert_equal 'rufioを中断しました', Rufio::ConfigLoader.message('app.interrupted')
    assert_equal 'ファイルが見つかりません', Rufio::ConfigLoader.message('file.not_found')
    assert_equal 'rufio ヘルスチェック', Rufio::ConfigLoader.message('health.title')
    
    # Switch to English
    Rufio::Config.current_language = 'en'
    
    # All operations should now use English
    assert_equal 'rufio interrupted', Rufio::ConfigLoader.message('app.interrupted')
    assert_equal 'File not found', Rufio::ConfigLoader.message('file.not_found')
    assert_equal 'rufio Health Check', Rufio::ConfigLoader.message('health.title')
  end

  def test_config_loader_language_methods
    # Test default language detection
    language = Rufio::ConfigLoader.language
    assert_includes %w[en ja], language
    
    # Test language setting through ConfigLoader
    Rufio::ConfigLoader.set_language('ja')
    assert_equal 'ja', Rufio::Config.current_language
    assert_equal 'ja', Rufio::ConfigLoader.language
    
    Rufio::ConfigLoader.set_language('en')
    assert_equal 'en', Rufio::Config.current_language
    assert_equal 'en', Rufio::ConfigLoader.language
  end

  def test_all_message_keys_exist_in_both_languages
    # Get all message keys from English (complete set)
    en_keys = Rufio::Config::MESSAGES['en'].keys
    ja_keys = Rufio::Config::MESSAGES['ja'].keys
    
    # Verify Japanese has all the same keys
    missing_in_ja = en_keys - ja_keys
    assert_empty missing_in_ja, "Missing Japanese translations for keys: #{missing_in_ja.join(', ')}"
    
    # Verify no extra keys in Japanese (consistency check)
    extra_in_ja = ja_keys - en_keys
    assert_empty extra_in_ja, "Extra Japanese keys not in English: #{extra_in_ja.join(', ')}"
  end

  def test_message_completeness
    # Test that all messages have non-empty values
    %w[en ja].each do |lang|
      Rufio::Config.current_language = lang
      
      Rufio::Config::MESSAGES[lang].each do |key, message|
        refute_empty message, "Empty message for key '#{key}' in language '#{lang}'"
        assert message.is_a?(String), "Non-string message for key '#{key}' in language '#{lang}'"
      end
    end
  end
end