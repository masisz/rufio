# frozen_string_literal: true

require 'test_helper'

class TestConfig < Minitest::Test
  def setup
    # Reset language to clean state before each test
    Rufio::Config.reset_language!
  end

  def teardown
    # Reset language after each test
    Rufio::Config.reset_language!
  end

  def test_default_language_is_english
    assert_equal 'en', Rufio::Config.current_language
  end

  def test_can_set_supported_language
    Rufio::Config.current_language = 'ja'
    assert_equal 'ja', Rufio::Config.current_language
    
    Rufio::Config.current_language = 'en'
    assert_equal 'en', Rufio::Config.current_language
  end

  def test_raises_error_for_unsupported_language
    assert_raises ArgumentError do
      Rufio::Config.current_language = 'fr'
    end
  end

  def test_message_returns_english_by_default
    message = Rufio::Config.message('app.interrupted')
    assert_equal 'rufio interrupted', message
  end

  def test_message_returns_japanese_when_set
    Rufio::Config.current_language = 'ja'
    message = Rufio::Config.message('app.interrupted')
    assert_equal 'rufioを中断しました', message
  end

  def test_message_falls_back_to_english_for_missing_key
    Rufio::Config.current_language = 'ja'
    message = Rufio::Config.message('nonexistent.key')
    assert_equal 'nonexistent.key', message # Falls back to key itself
  end

  def test_message_with_interpolation
    # Note: Current implementation doesn't use interpolation, but we test the interface
    message = Rufio::Config.message('file.read_error')
    assert message.is_a?(String)
    assert message.length > 0
  end

  def test_available_languages
    languages = Rufio::Config.available_languages
    assert_includes languages, 'en'
    assert_includes languages, 'ja'
    assert_equal 2, languages.length
  end

  def test_language_detection_from_env_rufio_lang
    with_env('BENIYA_LANG' => 'ja') do
      Rufio::Config.reset_language!
      assert_equal 'ja', Rufio::Config.current_language
    end
  end

  def test_language_detection_ignores_system_lang
    # LANG should be ignored, default to English
    with_env('LANG' => 'ja_JP.UTF-8', 'BENIYA_LANG' => nil) do
      Rufio::Config.reset_language!
      assert_equal 'en', Rufio::Config.current_language
    end
  end

  def test_language_detection_fallback_to_default
    with_env('LANG' => 'fr_FR.UTF-8', 'BENIYA_LANG' => nil) do
      Rufio::Config.reset_language!
      assert_equal 'en', Rufio::Config.current_language
    end
  end

  def test_rufio_lang_overrides_default
    with_env('LANG' => 'fr_FR.UTF-8', 'BENIYA_LANG' => 'ja') do
      Rufio::Config.reset_language!
      assert_equal 'ja', Rufio::Config.current_language
    end
  end

  private

  def with_env(env_vars)
    original_values = {}
    env_vars.each do |key, value|
      original_values[key] = ENV[key]
      if value.nil?
        ENV.delete(key)
      else
        ENV[key] = value
      end
    end

    yield

    # Restore original environment
    original_values.each do |key, value|
      if value.nil?
        ENV.delete(key)
      else
        ENV[key] = value
      end
    end
  end
end