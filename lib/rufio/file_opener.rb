# frozen_string_literal: true

require 'shellwords'

module Rufio
  class FileOpener
    def initialize
      @config_loader = ConfigLoader
    end

    def open_file(file_path)
      return false unless File.exist?(file_path)
      return false if File.directory?(file_path)

      application = find_application_for_file(file_path)
      execute_command(application, file_path)
    end

    def open_file_with_line(file_path, line_number)
      return false unless File.exist?(file_path)
      return false if File.directory?(file_path)

      application = find_application_for_file(file_path)
      execute_command_with_line(application, file_path, line_number)
    end

    def open_directory_in_explorer(directory_path)
      return false unless File.exist?(directory_path)
      return false unless File.directory?(directory_path)

      execute_explorer_command(directory_path)
    end

    private

    def find_application_for_file(file_path)
      extension = File.extname(file_path).downcase.sub('.', '')
      applications = @config_loader.applications

      applications.each do |extensions, app|
        return app if extensions.is_a?(Array) && extensions.include?(extension)
      end

      applications[:default] || 'open'
    end

    def execute_command(application, file_path)
      path = safe_path(file_path)

      case RbConfig::CONFIG['host_os']
      when /mswin|mingw|cygwin/
        # Windows: cmd.exe を経由せず（%VAR% や & の展開を避ける）既定アプリで開く
        run_command(['rundll32', 'url.dll,FileProtocolHandler', path])
      when /darwin/
        # macOS
        if application == 'open'
          run_command(['open', path])
        else
          # VSCodeなど特定のアプリケーション
          run_command([*application_argv(application), path])
        end
      else
        # Linux/Unix
        if application == 'open'
          run_command(['xdg-open', path])
        else
          run_command([*application_argv(application), path])
        end
      end
    rescue StandardError => e
      warn "Failed to open file: #{e.message}"
      false
    end

    def execute_command_with_line(application, file_path, line_number)
      path = safe_path(file_path)
      line = line_number.to_i
      app = application_argv(application)

      case RbConfig::CONFIG['host_os']
      when /mswin|mingw|cygwin/
        # Windows
        if application.include?('code')
          run_command([*app, '--goto', "#{path}:#{line}"])
        else
          run_command(['rundll32', 'url.dll,FileProtocolHandler', path])
        end
      when /darwin/
        # macOS
        if application == 'open'
          run_command(['open', path])
        elsif application.include?('code')
          run_command([*app, '--goto', "#{path}:#{line}"])
        elsif application.include?('vim') || application.include?('nvim')
          run_command([*app, "+#{line}", path])
        else
          run_command([*app, path])
        end
      else
        # Linux/Unix
        if application == 'open'
          run_command(['xdg-open', path])
        elsif application.include?('code')
          run_command([*app, '--goto', "#{path}:#{line}"])
        elsif application.include?('vim') || application.include?('nvim')
          run_command([*app, "+#{line}", path])
        else
          run_command([*app, path])
        end
      end
    rescue StandardError => e
      warn "Failed to open file: #{e.message}"
      false
    end

    # シェルを介さず配列形式で実行する（ファイル名経由のコマンドインジェクション防止）
    def run_command(argv)
      system(*argv)
    end

    # 設定のアプリケーション指定（例: "code -r"）を引数配列に分解する
    def application_argv(application)
      if RbConfig::CONFIG['host_os'] =~ /mswin|mingw|cygwin/
        # Windows のパスはバックスラッシュを含むため POSIX 分割は使わない
        File.exist?(application) ? [application] : application.split
      else
        Shellwords.split(application)
      end
    end

    # '-' で始まるパスがオプションとして解釈されないようにする
    def safe_path(path)
      path.start_with?('-') ? File.join('.', path) : path
    end

    def execute_explorer_command(directory_path)
      path = safe_path(directory_path)

      case RbConfig::CONFIG['host_os']
      when /mswin|mingw|cygwin/
        # Windows
        run_command(['explorer', path])
      when /darwin/
        # macOS
        run_command(['open', path])
      else
        # Linux/Unix
        run_command(['xdg-open', path])
      end
    rescue StandardError => e
      warn "Failed to open directory: #{e.message}"
      false
    end
  end
end

