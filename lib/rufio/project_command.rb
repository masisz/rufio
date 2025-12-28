# frozen_string_literal: true

require 'open3'
require 'fileutils'
require 'shellwords'

module Rufio
  # プロジェクトコマンド - 登録されたコマンドを実行する
  class ProjectCommand
    def initialize(log_dir, scripts_dir = nil)
      @log_dir = log_dir
      @scripts_dir = scripts_dir || ConfigLoader.scripts_dir
      @registered_commands = {}

      # スクリプトディレクトリが存在しなければ作成
      ensure_scripts_directory
    end

    # コマンドを実行する
    # @param command [String] 実行するコマンド
    # @param working_dir [String] 作業ディレクトリ
    # @return [Hash] 実行結果 { success: Boolean, output: String, error: String }
    def execute(command, working_dir)
      begin
        stdout, stderr, status = Open3.capture3(command, chdir: working_dir)

        {
          success: status.success?,
          output: stdout,
          error: stderr
        }
      rescue StandardError => e
        {
          success: false,
          output: '',
          error: "Command not found or failed to execute: #{e.message}"
        }
      end
    end

    # 登録されたコマンドを実行する
    # @param command_name [String] コマンド名
    # @param working_dir [String] 作業ディレクトリ
    # @return [Hash] 実行結果
    def execute_registered(command_name, working_dir)
      unless @registered_commands.key?(command_name)
        return {
          success: false,
          output: '',
          error: "Command '#{command_name}' not found in registered commands"
        }
      end

      command = @registered_commands[command_name]
      execute(command, working_dir)
    end

    # コマンドを登録する
    # @param name [String] コマンド名
    # @param command [String] コマンド文字列
    def register(name, command)
      @registered_commands[name] = command
    end

    # 登録されているコマンドの一覧を取得
    # @return [Array<String>] コマンド名の配列
    def list_registered_commands
      @registered_commands.keys
    end

    # 左画面用の表示データを取得
    # @return [Array<String>] コマンド名の配列
    def get_left_pane_data
      @registered_commands.keys.map.with_index(1) do |name, index|
        "#{index}. #{name}"
      end
    end

    # スクリプトディレクトリ内のRubyスクリプト一覧を取得
    # @return [Array<String>] スクリプトファイル名の配列
    def list_scripts
      return [] unless Dir.exist?(@scripts_dir)

      Dir.glob(File.join(@scripts_dir, '*.rb')).map do |path|
        File.basename(path)
      end.sort
    end

    # スクリプトを実行する
    # @param script_name [String] スクリプトファイル名
    # @param working_dir [String] 作業ディレクトリ
    # @return [Hash] 実行結果
    def execute_script(script_name, working_dir)
      script_path = File.join(@scripts_dir, script_name)

      unless File.exist?(script_path)
        return {
          success: false,
          output: '',
          error: "Script not found: #{script_name}"
        }
      end

      # Rubyスクリプトとして実行
      execute("ruby #{script_path.shellescape}", working_dir)
    end

    # スクリプトディレクトリのパスを取得
    # @return [String] スクリプトディレクトリのパス
    def scripts_dir
      @scripts_dir
    end

    private

    # スクリプトディレクトリを確保する
    def ensure_scripts_directory
      return if Dir.exist?(@scripts_dir)

      FileUtils.mkdir_p(@scripts_dir)

      # サンプルスクリプトを作成
      create_sample_script
    end

    # サンプルスクリプトを作成
    def create_sample_script
      sample_script = File.join(@scripts_dir, 'hello.rb')
      return if File.exist?(sample_script)

      File.write(sample_script, <<~RUBY)
        #!/usr/bin/env ruby
        # Sample script for rufio project mode
        # This script will be executed in the selected project directory

        puts "Hello from rufio script!"
        puts "Current directory: \#{Dir.pwd}"
        puts "Files in directory:"
        Dir.glob('*').each do |file|
          puts "  - \#{file}"
        end
      RUBY

      File.chmod(0755, sample_script)
    end
  end
end
