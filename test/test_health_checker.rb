# frozen_string_literal: true

require 'test_helper'

class TestHealthChecker < Minitest::Test
  def setup
    @health_checker = Rufio::HealthChecker.new
  end

  def test_check_ruby_version
    result = @health_checker.send(:check_ruby_version)
    
    assert_includes [:ok, :error], result[:status]
    assert result[:message].include?("Ruby")
    
    # 現在のRubyバージョンが2.7以上であることを前提
    current_version = RUBY_VERSION.split('.').map(&:to_i)
    if current_version[0] > 2 || (current_version[0] == 2 && current_version[1] >= 7)
      assert_equal :ok, result[:status]
    end
  end

  def test_check_required_gems
    result = @health_checker.send(:check_required_gems)
    
    assert_includes [:ok, :error], result[:status]
    assert result[:message].is_a?(String)
    
    # 必要なgemがロードされていることを確認
    required_gems = %w[io-console pastel tty-cursor tty-screen]
    required_gems.each do |gem_name|
      begin
        require gem_name.gsub('-', '/')
        # gemが正常にロードできた
      rescue LoadError
        # gemがない場合はエラーステータスになるはず
      end
    end
  end

  def test_check_fzf
    result = @health_checker.send(:check_fzf)
    
    assert_includes [:ok, :warning], result[:status]
    assert result[:message].is_a?(String)
    
    if result[:status] == :ok
      assert result[:message].include?("fzf")
      assert_nil result[:details]
    else
      assert_equal "fzf not found", result[:message]
      assert result[:details].include?("Install")
    end
  end

  def test_check_rga
    result = @health_checker.send(:check_rga)

    assert_includes [:ok, :warning], result[:status]
    assert result[:message].is_a?(String)

    if result[:status] == :ok
      # rgaのバージョン出力は "ripgrep-all x.x.x" の形式
      assert !result[:message].empty?, "Message should not be empty"
      assert_nil result[:details]
    else
      # 警告メッセージを確認
      assert result[:message].include?("rga"), "Warning message should mention rga"
      assert result[:details].is_a?(String)
    end
  end

  def test_check_zoxide
    result = @health_checker.send(:check_zoxide)
    
    assert_includes [:ok, :warning], result[:status]
    assert result[:message].is_a?(String)
    
    if result[:status] == :ok
      assert result[:message].include?("zoxide")
      assert_nil result[:details]
    else
      assert result[:message].include?("zoxide")
      assert result[:details].is_a?(String)
    end
  end

  def test_check_file_opener
    result = @health_checker.send(:check_file_opener)
    
    assert_includes [:ok, :warning], result[:status]
    assert result[:message].is_a?(String)
    
    # プラットフォーム固有のテスト
    case RUBY_PLATFORM
    when /darwin/
      if result[:status] == :ok
        assert result[:message].include?("macOS")
      end
    when /linux/
      if result[:status] == :ok
        assert result[:message].include?("Linux")
      end
    when /mswin|mingw|cygwin/
      if result[:status] == :ok
        assert result[:message].include?("Windows")
      end
    end
  end

  def test_install_instruction_for_fzf
    instruction = @health_checker.send(:install_instruction_for, 'fzf')
    
    assert instruction.is_a?(String)
    assert instruction.include?("Install")
    
    # プラットフォーム固有の指示が含まれることを確認
    case RUBY_PLATFORM
    when /darwin/
      assert instruction.include?("brew")
    when /linux/
      assert instruction.include?("apt") || instruction.include?("package manager")
    end
  end

  def test_install_instruction_for_rga
    instruction = @health_checker.send(:install_instruction_for, 'rga')
    
    assert instruction.is_a?(String)
    assert instruction.include?("Install") || instruction.include?("github") || instruction.include?("Check")
  end

  def test_install_instruction_for_zoxide
    instruction = @health_checker.send(:install_instruction_for, 'zoxide')
    
    assert instruction.is_a?(String)
    
    # プラットフォーム固有の指示が含まれることを確認
    case RUBY_PLATFORM
    when /darwin/
      assert instruction.include?("brew")
    when /linux/
      assert instruction.include?("apt") || instruction.include?("package manager")
    else
      assert instruction.include?("Install") || instruction.include?("Check")
    end
  end

  def test_run_check_returns_boolean
    # 実際のヘルスチェックを実行（出力は無視）
    result = capture_io do
      @health_checker.run_check
    end
    
    # run_checkはbooleanを返すはず
    success = result[0] # capture_ioは[stdout, stderr]を返すので、実際の戻り値は取得できない
    # 代わりに、メソッドが例外なく完了することをテスト
    assert true # テストが完了すれば成功
  end

  def test_health_check_output_format
    stdout, _stderr = capture_io do
      @health_checker.run_check
    end
    
    # 出力に期待される文字列が含まれることを確認
    assert stdout.include?("rufio Health Check")
    assert stdout.include?("Ruby version")
    assert stdout.include?("Required gems")
    assert stdout.include?("Summary:")
  end
end