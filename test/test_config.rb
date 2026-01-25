# frozen_string_literal: true

require_relative 'test_helper'
require_relative '../lib/rufio/bookmark_storage'

Minitest.autorun

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

  def test_message_returns_same_for_japanese_setting
    # Both languages now use English messages
    Rufio::Config.current_language = 'ja'
    message = Rufio::Config.message('app.interrupted')
    assert_equal 'rufio interrupted', message
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

  # ========================================
  # ConfigLoader ブックマーク統合テスト
  # ========================================

  def test_config_loader_bookmark_storage_returns_yaml_storage
    storage = Rufio::ConfigLoader.bookmark_storage
    assert_kind_of Rufio::YamlBookmarkStorage, storage
  end

  def test_config_loader_migrate_bookmarks_if_needed
    # テスト用の一時ディレクトリを作成
    test_dir = File.join(Dir.tmpdir, 'rufio_config_test')
    FileUtils.mkdir_p(test_dir)

    json_file = File.join(test_dir, 'bookmarks.json')
    yaml_file = File.join(test_dir, 'config.yml')

    begin
      # JSONファイルにブックマークを保存
      File.write(json_file, '[{"path": "/test/path", "name": "test"}]')

      # マイグレーションを実行
      result = Rufio::ConfigLoader.migrate_bookmarks_if_needed(json_file, yaml_file)

      assert result
      # YAMLファイルにブックマークが移行されている
      assert File.exist?(yaml_file)
      content = YAML.safe_load(File.read(yaml_file), symbolize_names: true)
      assert_equal 1, content[:bookmarks].length
      # JSONファイルはバックアップされている
      assert File.exist?("#{json_file}.bak")
    ensure
      FileUtils.rm_rf(test_dir)
    end
  end

  def test_config_loader_migrate_bookmarks_skips_if_no_json
    test_dir = File.join(Dir.tmpdir, 'rufio_config_test')
    FileUtils.mkdir_p(test_dir)

    json_file = File.join(test_dir, 'nonexistent.json')
    yaml_file = File.join(test_dir, 'config.yml')

    begin
      result = Rufio::ConfigLoader.migrate_bookmarks_if_needed(json_file, yaml_file)

      refute result
      refute File.exist?(yaml_file)
    ensure
      FileUtils.rm_rf(test_dir)
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