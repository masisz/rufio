# frozen_string_literal: true

require_relative "test_helper"

class TestConfigLoader < Minitest::Test
  def setup
    # テスト前にキャッシュをクリア
    Rufio::ConfigLoader.instance_variable_set(:@config, nil)
    @original_config_path = Rufio::ConfigLoader::CONFIG_PATH

    # テスト用の一時HOMEディレクトリを作成
    @temp_dir = Dir.mktmpdir
    @original_home = ENV['HOME']
    ENV['HOME'] = @temp_dir
  end

  def teardown
    # CONFIG_PATHを元に戻す（警告を避けるため remove_const してから const_set）
    Rufio::ConfigLoader.send(:remove_const, :CONFIG_PATH) if Rufio::ConfigLoader.const_defined?(:CONFIG_PATH)
    Rufio::ConfigLoader.const_set(:CONFIG_PATH, @original_config_path)
    # HOME環境変数を復元
    ENV['HOME'] = @original_home
    # 一時ディレクトリを削除
    FileUtils.rm_rf(@temp_dir) if @temp_dir && Dir.exist?(@temp_dir)
    # テスト後にもキャッシュをクリア
    Rufio::ConfigLoader.instance_variable_set(:@config, nil)
  end

  def test_load_default_config_when_no_file_exists
    # 設定ファイルが存在しない場合のテスト
    # パスを一時的に存在しないパスに変更（警告を避けるため remove_const してから const_set）
    Rufio::ConfigLoader.send(:remove_const, :CONFIG_PATH) if Rufio::ConfigLoader.const_defined?(:CONFIG_PATH)
    Rufio::ConfigLoader.const_set(:CONFIG_PATH, "/tmp/nonexistent_config.rb")
    # キャッシュをクリアして再読み込みを強制
    Rufio::ConfigLoader.instance_variable_set(:@config, nil)

    config = Rufio::ConfigLoader.load_config

    # デフォルト設定が返されることを確認
    assert_instance_of Hash, config
    assert config.key?(:applications)
    assert config.key?(:colors)
    assert config.key?(:keybinds)

    # アプリケーションの設定を確認
    applications = config[:applications]
    assert_equal 'code', applications[%w[txt md rb py js html css json xml yaml yml]]
    assert_equal 'open', applications[:default]
  end

  def test_applications_method
    # テスト環境では設定ファイルが存在しないため、デフォルト設定が使われる
    Rufio::ConfigLoader.instance_variable_set(:@config, nil)
    Rufio::ConfigLoader.reload_config!

    applications = Rufio::ConfigLoader.applications
    assert_instance_of Hash, applications

    # applicationsが適切なキーと値を持っていることを確認
    # ユーザー設定ファイルが存在する場合も考慮して、柔軟にテスト
    assert applications.key?(:default), "applications should have :default key"
    assert applications[:default].is_a?(String), "applications[:default] should be a String"

    # 少なくとも1つのファイルタイプのマッピングが存在することを確認
    assert applications.any? { |k, v| k.is_a?(Array) && v.is_a?(String) },
           "applications should have at least one file type mapping"
  end

  def test_colors_method
    colors = Rufio::ConfigLoader.colors
    assert_instance_of Hash, colors
    # 新しいHSL形式の色設定をテスト
    assert_equal({ hsl: [220, 80, 60] }, colors[:directory])
    assert_equal({ hsl: [0, 0, 90] }, colors[:file])
    assert_equal({ hsl: [120, 70, 50] }, colors[:executable])
    assert_equal({ hsl: [50, 90, 70] }, colors[:selected])
    assert_equal({ hsl: [180, 60, 65] }, colors[:preview])
  end

  def test_command_history_size_default
    # COMMAND_HISTORY_SIZEが設定されていない場合、デフォルト値1000を返す
    Rufio::ConfigLoader.instance_variable_set(:@config, nil)
    Rufio::ConfigLoader.reload_config!

    history_size = Rufio::ConfigLoader.command_history_size
    assert_equal 1000, history_size
  end

  def test_keybinds_method
    keybinds = Rufio::ConfigLoader.keybinds
    assert_instance_of Hash, keybinds
    assert_equal %w[q ESC], keybinds[:quit]
    assert_equal %w[o SPACE], keybinds[:open_file]
  end

  def test_command_history_size_custom
    # カスタム設定を作成
    config_dir = File.join(@temp_dir, '.config', 'rufio')
    FileUtils.mkdir_p(config_dir)
    config_file = File.join(config_dir, 'config.rb')

    File.write(config_file, <<~RUBY)
      COMMAND_HISTORY_SIZE = 500
      APPLICATIONS = { :default => 'open' }
      COLORS = {}
      KEYBINDS = {}
    RUBY

    # CONFIG_PATHを更新
    Rufio::ConfigLoader.const_set(:CONFIG_PATH, config_file)
    Rufio::ConfigLoader.instance_variable_set(:@config, nil)

    history_size = Rufio::ConfigLoader.command_history_size
    assert_equal 500, history_size
  end

  def test_reload_config
    # 最初の読み込み
    config1 = Rufio::ConfigLoader.load_config

    # リロード
    config2 = Rufio::ConfigLoader.reload_config!

    # 設定が再読み込みされることを確認（同じ内容でも問題ない）
    assert_equal config1, config2
  end
end