# frozen_string_literal: true

require 'test_helper'
require 'minitest/autorun'

class TestCommandModeUI < Minitest::Test
  def setup
    # プラグインマネージャーをリセット
    Rufio::PluginManager.instance_variable_set(:@plugins, [])
    Rufio::PluginManager.instance_variable_set(:@enabled_plugins, nil)

    # テスト用プラグインを作成
    @test_plugin = Class.new(Rufio::Plugin) do
      def name
        "TestPlugin"
      end

      def description
        "テスト用プラグイン"
      end

      def commands
        {
          hello: method(:say_hello),
          help: method(:show_help),
          health: method(:health_check)
        }
      end

      private

      def say_hello
        "Hello from TestPlugin!"
      end

      def show_help
        "Help information"
      end

      def health_check
        "Health: OK"
      end
    end

    # プラグインを登録
    Rufio::Plugins.const_set(:TestPlugin, @test_plugin)
    Rufio::PluginManager.register(@test_plugin)
    Rufio::PluginManager.instance_variable_set(:@enabled_plugins, nil)

    @command_mode = Rufio::CommandMode.new
    @dialog_renderer = Rufio::DialogRenderer.new
    @command_mode_ui = Rufio::CommandModeUI.new(@command_mode, @dialog_renderer)
  end

  def teardown
    # テスト後のクリーンアップ
    Rufio::PluginManager.instance_variable_set(:@plugins, [])
    Rufio::PluginManager.instance_variable_set(:@enabled_plugins, nil)

    # テスト用プラグインを削除
    if Rufio::Plugins.const_defined?(:TestPlugin, false)
      Rufio::Plugins.send(:remove_const, :TestPlugin)
    end
  end

  # === Tab補完機能のテスト ===

  def test_command_mode_ui_class_exists
    assert defined?(Rufio::CommandModeUI), "Rufio::CommandModeUI クラスが定義されていません"
  end

  def test_autocomplete_no_input
    # 入力がない場合、全てのコマンドを返す
    suggestions = @command_mode_ui.autocomplete("")

    assert_includes suggestions, "hello"
    assert_includes suggestions, "help"
    assert_includes suggestions, "health"
  end

  def test_autocomplete_partial_match
    # 部分一致で補完候補を返す
    suggestions = @command_mode_ui.autocomplete("he")

    assert_includes suggestions, "hello"
    assert_includes suggestions, "help"
    assert_includes suggestions, "health"
  end

  def test_autocomplete_exact_prefix
    # より具体的なプレフィックスで絞り込み
    suggestions = @command_mode_ui.autocomplete("hel")

    assert_includes suggestions, "hello"
    assert_includes suggestions, "help"
    refute_includes suggestions, "health"
  end

  def test_autocomplete_single_match
    # 一つだけマッチする場合
    suggestions = @command_mode_ui.autocomplete("hello")

    assert_equal ["hello"], suggestions
  end

  def test_autocomplete_no_match
    # マッチするものがない場合
    suggestions = @command_mode_ui.autocomplete("xyz")

    assert_empty suggestions
  end

  def test_complete_command_single_match
    # 一つだけマッチする場合は自動補完
    completed = @command_mode_ui.complete_command("hello")

    assert_equal "hello", completed
  end

  def test_complete_command_multiple_matches
    # 複数マッチする場合は共通部分まで補完
    completed = @command_mode_ui.complete_command("he")

    # "hello", "help", "health" の共通プレフィックスは "he"
    assert_equal "he", completed
  end

  def test_complete_command_no_match
    # マッチしない場合は元の入力を返す
    completed = @command_mode_ui.complete_command("xyz")

    assert_equal "xyz", completed
  end

  # === フローティングウィンドウ表示のテスト ===

  def test_show_result_success
    # 成功メッセージの表示
    result = "Command executed successfully!"

    # モック化してメソッドが呼ばれることを確認
    draw_called = false
    clear_called = false

    @dialog_renderer.stub :draw_floating_window, ->(x, y, w, h, title, content, opts) {
      draw_called = true
      assert_equal "コマンド実行結果", title
      assert_includes content, result
    } do
      @dialog_renderer.stub :clear_area, ->(*) { clear_called = true } do
        STDIN.stub :getch, "\r" do
          @command_mode_ui.show_result(result)
        end
      end
    end

    assert draw_called, "draw_floating_window が呼ばれていません"
    assert clear_called, "clear_area が呼ばれていません"
  end

  def test_show_result_error
    # エラーメッセージの表示
    result = "⚠️  コマンドが見つかりません: xyz"

    draw_called = false

    @dialog_renderer.stub :draw_floating_window, ->(x, y, w, h, title, content, opts) {
      draw_called = true
      assert_includes content, result
      # エラーの場合は色が変わることを確認
      assert_equal "\e[31m", opts[:border_color] if result.include?("⚠️")
    } do
      @dialog_renderer.stub :clear_area, ->(*) {} do
        STDIN.stub :getch, "\r" do
          @command_mode_ui.show_result(result)
        end
      end
    end

    assert draw_called, "draw_floating_window が呼ばれていません"
  end

  def test_show_result_multiline
    # 複数行の結果表示
    result = "Line 1\nLine 2\nLine 3"

    draw_called = false

    @dialog_renderer.stub :draw_floating_window, ->(x, y, w, h, title, content, opts) {
      draw_called = true
      # 空行 + Line1 + Line2 + Line3 + 空行 + "Press any key to close"
      # 空行でない行は 4行（結果3行 + プロンプト1行）
      assert_equal 4, content.select { |line| !line.empty? }.length
    } do
      @dialog_renderer.stub :clear_area, ->(*) {} do
        STDIN.stub :getch, "\r" do
          @command_mode_ui.show_result(result)
        end
      end
    end

    assert draw_called, "draw_floating_window が呼ばれていません"
  end

  def test_show_result_nil
    # nil の場合は何も表示しない
    draw_called = false

    @dialog_renderer.stub :draw_floating_window, ->(*) { draw_called = true } do
      @command_mode_ui.show_result(nil)
    end

    refute draw_called, "nil の場合は draw_floating_window を呼んではいけません"
  end

  def test_show_result_empty_string
    # 空文字列の場合は何も表示しない
    draw_called = false

    @dialog_renderer.stub :draw_floating_window, ->(*) { draw_called = true } do
      @command_mode_ui.show_result("")
    end

    refute draw_called, "空文字列の場合は draw_floating_window を呼んではいけません"
  end

  # === コマンド入力フローティングウィンドウのテスト ===

  def test_show_input_prompt_basic
    # 基本的な入力プロンプトの表示
    input = "hello"
    draw_called = false

    @dialog_renderer.stub :draw_floating_window, ->(x, y, w, h, title, content, opts) {
      draw_called = true
      assert_equal "コマンドモード", title
      assert_includes content.join("\n"), input
    } do
      @command_mode_ui.show_input_prompt(input)
    end

    assert draw_called, "draw_floating_window が呼ばれていません"
  end

  def test_show_input_prompt_empty_input
    # 空の入力の場合
    input = ""
    draw_called = false

    @dialog_renderer.stub :draw_floating_window, ->(x, y, w, h, title, content, opts) {
      draw_called = true
      assert_includes content.join("\n"), "_"  # カーソルが表示される
    } do
      @command_mode_ui.show_input_prompt(input)
    end

    assert draw_called, "draw_floating_window が呼ばれていません"
  end

  def test_show_input_prompt_with_suggestions
    # 補完候補付きの入力プロンプト
    input = "he"
    suggestions = ["hello", "help", "health"]
    draw_called = false

    @dialog_renderer.stub :draw_floating_window, ->(x, y, w, h, title, content, opts) {
      draw_called = true
      # 補完候補が表示されることを確認
      content_text = content.join("\n")
      suggestions.each do |suggestion|
        assert_includes content_text, suggestion
      end
    } do
      @command_mode_ui.show_input_prompt(input, suggestions)
    end

    assert draw_called, "draw_floating_window が呼ばれていません"
  end

  def test_show_input_prompt_color
    # プロンプトの色が青であることを確認
    input = "test"
    draw_called = false

    @dialog_renderer.stub :draw_floating_window, ->(x, y, w, h, title, content, opts) {
      draw_called = true
      assert_equal "\e[34m", opts[:border_color]  # Blue
    } do
      @command_mode_ui.show_input_prompt(input)
    end

    assert draw_called, "draw_floating_window が呼ばれていません"
  end

  # === 統合テスト ===

  def test_prompt_command_with_autocomplete
    # Tab キーでの補完動作をシミュレート
    # これは実際のキー入力をモックするのが難しいため、
    # autocomplete メソッドが正しく動作することを確認

    # 補完候補があることを確認
    suggestions = @command_mode_ui.autocomplete("he")
    assert suggestions.length > 1

    # 補完が適用されることを確認
    completed = @command_mode_ui.complete_command("he")
    assert_equal "he", completed # 共通プレフィックス
  end

  def test_command_mode_ui_initialization
    # CommandModeUI が正しく初期化できることを確認
    ui = Rufio::CommandModeUI.new(@command_mode, @dialog_renderer)

    refute_nil ui
    assert_respond_to ui, :autocomplete
    assert_respond_to ui, :complete_command
    assert_respond_to ui, :show_result
  end

  # === Hash形式の結果表示テスト ===

  def test_show_result_hash_success
    # Hash形式の成功結果を表示
    result = { success: true, output: "command output", stderr: "" }
    draw_called = false

    @dialog_renderer.stub :draw_floating_window, ->(x, y, w, h, title, content, opts) {
      draw_called = true
      assert_equal "コマンド実行結果", title
      content_text = content.join("\n")
      assert_includes content_text, "command output"
      # 成功の場合は緑色
      assert_equal "\e[32m", opts[:border_color]
    } do
      @dialog_renderer.stub :clear_area, ->(*) {} do
        STDIN.stub :getch, "\r" do
          @command_mode_ui.show_result(result)
        end
      end
    end

    assert draw_called, "draw_floating_window が呼ばれていません"
  end

  def test_show_result_hash_error
    # Hash形式のエラー結果を表示
    result = { success: false, error: "Command failed (exit code: 1)", output: "", stderr: "error message" }
    draw_called = false

    @dialog_renderer.stub :draw_floating_window, ->(x, y, w, h, title, content, opts) {
      draw_called = true
      content_text = content.join("\n")
      assert_includes content_text, "Command failed"
      assert_includes content_text, "error message"
      # エラーの場合は赤色
      assert_equal "\e[31m", opts[:border_color]
    } do
      @dialog_renderer.stub :clear_area, ->(*) {} do
        STDIN.stub :getch, "\r" do
          @command_mode_ui.show_result(result)
        end
      end
    end

    assert draw_called, "draw_floating_window が呼ばれていません"
  end

  def test_show_result_hash_with_stderr
    # 標準エラー出力を含むHash結果を表示
    result = { success: true, output: "stdout", stderr: "warning message" }
    draw_called = false

    @dialog_renderer.stub :draw_floating_window, ->(x, y, w, h, title, content, opts) {
      draw_called = true
      content_text = content.join("\n")
      assert_includes content_text, "stdout"
      assert_includes content_text, "warning message"
    } do
      @dialog_renderer.stub :clear_area, ->(*) {} do
        STDIN.stub :getch, "\r" do
          @command_mode_ui.show_result(result)
        end
      end
    end

    assert draw_called, "draw_floating_window が呼ばれていません"
  end

  def test_show_result_hash_multiline_output
    # 複数行の出力を含むHash結果を表示
    result = { success: true, output: "line1\nline2\nline3", stderr: "" }
    draw_called = false

    @dialog_renderer.stub :draw_floating_window, ->(x, y, w, h, title, content, opts) {
      draw_called = true
      content_text = content.join("\n")
      assert_includes content_text, "line1"
      assert_includes content_text, "line2"
      assert_includes content_text, "line3"
    } do
      @dialog_renderer.stub :clear_area, ->(*) {} do
        STDIN.stub :getch, "\r" do
          @command_mode_ui.show_result(result)
        end
      end
    end

    assert draw_called, "draw_floating_window が呼ばれていません"
  end
end
