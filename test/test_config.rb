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

  def test_config_loader_load_bookmarks
    # テスト用の一時ディレクトリを作成
    test_dir = File.join(Dir.tmpdir, 'rufio_config_test')
    FileUtils.mkdir_p(test_dir)

    yaml_file = File.join(test_dir, 'config.yml')
    bookmarks_file = File.join(test_dir, 'bookmarks.yml')

    begin
      # YAMLファイルにブックマークを保存（古い形式）
      File.write(yaml_file, <<~YAML)
        bookmarks:
          - path: /test/path
            name: test
      YAML

      # 一時的にパスを変更してテスト
      original_yaml_path = Rufio::ConfigLoader::YAML_CONFIG_PATH
      original_bookmarks_path = Rufio::ConfigLoader::BOOKMARKS_YML

      Rufio::ConfigLoader.send(:remove_const, :YAML_CONFIG_PATH)
      Rufio::ConfigLoader.const_set(:YAML_CONFIG_PATH, yaml_file)
      Rufio::ConfigLoader.send(:remove_const, :BOOKMARKS_YML)
      Rufio::ConfigLoader.const_set(:BOOKMARKS_YML, bookmarks_file)

      bookmarks = Rufio::ConfigLoader.load_bookmarks
      assert_equal 1, bookmarks.length
      assert_equal '/test/path', bookmarks[0][:path]
      assert_equal 'test', bookmarks[0][:name]

      # 元に戻す
      Rufio::ConfigLoader.send(:remove_const, :YAML_CONFIG_PATH)
      Rufio::ConfigLoader.const_set(:YAML_CONFIG_PATH, original_yaml_path)
      Rufio::ConfigLoader.send(:remove_const, :BOOKMARKS_YML)
      Rufio::ConfigLoader.const_set(:BOOKMARKS_YML, original_bookmarks_path)
    ensure
      FileUtils.rm_rf(test_dir)
    end
  end

  # ========================================
  # Config YAML読み込みテスト
  # ========================================

  def test_config_yaml_config_path
    assert_equal File.expand_path('~/.config/rufio/config.yml'), Rufio::Config::YAML_CONFIG_PATH
  end

  def test_config_local_yaml_path
    assert_equal './rufio.yml', Rufio::Config::LOCAL_YAML_PATH
  end

  def test_config_load_yaml_config_returns_empty_hash_when_file_not_exists
    result = Rufio::Config.load_yaml_config('/nonexistent/path.yml')
    assert_equal({}, result)
  end

  def test_config_load_yaml_config_reads_yaml_file
    test_dir = File.join(Dir.tmpdir, 'rufio_config_yaml_test')
    FileUtils.mkdir_p(test_dir)
    yaml_file = File.join(test_dir, 'test_config.yml')

    begin
      File.write(yaml_file, <<~YAML)
        script_paths:
          - /test/scripts
          - ~/my-scripts
        bookmarks:
          - path: /home/user/docs
            name: Documents
      YAML

      result = Rufio::Config.load_yaml_config(yaml_file)

      assert_equal ['/test/scripts', '~/my-scripts'], result[:script_paths]
      assert_equal 1, result[:bookmarks].length
      assert_equal '/home/user/docs', result[:bookmarks][0][:path]
    ensure
      FileUtils.rm_rf(test_dir)
    end
  end

  def test_config_save_yaml_config
    test_dir = File.join(Dir.tmpdir, 'rufio_config_yaml_save_test')
    FileUtils.mkdir_p(test_dir)
    yaml_file = File.join(test_dir, 'test_config.yml')

    begin
      # 新しいファイルに保存
      Rufio::Config.save_yaml_config(yaml_file, :script_paths, ['/new/path'])

      result = Rufio::Config.load_yaml_config(yaml_file)
      assert_equal ['/new/path'], result[:script_paths]

      # 既存のファイルに別のキーを追加
      Rufio::Config.save_yaml_config(yaml_file, :bookmarks, [{ path: '/test', name: 'Test' }])

      result = Rufio::Config.load_yaml_config(yaml_file)
      assert_equal ['/new/path'], result[:script_paths]
      assert_equal 1, result[:bookmarks].length
    ensure
      FileUtils.rm_rf(test_dir)
    end
  end

  def test_config_yaml_config_uses_default_path
    # デフォルトパスでのyaml_configメソッドをテスト
    # 実際のファイルがない場合は空のハッシュを返す
    result = Rufio::Config.yaml_config
    assert result.is_a?(Hash)
  end

  def test_config_reload_yaml_config
    Rufio::Config.reload_yaml_config!
    # エラーなく実行できればOK
    assert true
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