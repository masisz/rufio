# frozen_string_literal: true

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
      quoted_path = quote_shell_argument(file_path)

      case RbConfig::CONFIG['host_os']
      when /mswin|mingw|cygwin/
        # Windows
        system("start \"\" \"#{file_path}\"")
      when /darwin/
        # macOS
        if application == 'open'
          system("open #{quoted_path}")
        else
          # VSCodeなど特定のアプリケーション
          system("#{application} #{quoted_path}")
        end
      else
        # Linux/Unix
        if application == 'open'
          system("xdg-open #{quoted_path}")
        else
          system("#{application} #{quoted_path}")
        end
      end
    rescue StandardError => e
      warn "Failed to open file: #{e.message}"
      false
    end

    def execute_command_with_line(application, file_path, line_number)
      quoted_path = quote_shell_argument(file_path)

      case RbConfig::CONFIG['host_os']
      when /mswin|mingw|cygwin/
        # Windows
        if application.include?('code')
          system("#{application} --goto #{quoted_path}:#{line_number}")
        else
          system("start \"\" \"#{file_path}\"")
        end
      when /darwin/
        # macOS
        if application == 'open'
          system("open #{quoted_path}")
        elsif application.include?('code')
          system("#{application} --goto #{quoted_path}:#{line_number}")
        elsif application.include?('vim') || application.include?('nvim')
          system("#{application} +#{line_number} #{quoted_path}")
        else
          system("#{application} #{quoted_path}")
        end
      else
        # Linux/Unix
        if application == 'open'
          system("xdg-open #{quoted_path}")
        elsif application.include?('code')
          system("#{application} --goto #{quoted_path}:#{line_number}")
        elsif application.include?('vim') || application.include?('nvim')
          system("#{application} +#{line_number} #{quoted_path}")
        else
          system("#{application} #{quoted_path}")
        end
      end
    rescue StandardError => e
      warn "Failed to open file: #{e.message}"
      false
    end

    def quote_shell_argument(argument)
      if argument.include?(' ') || argument.include?("'") || argument.include?('"')
        '"' + argument.gsub('"', '\"') + '"'
      else
        argument
      end
    end

    def execute_explorer_command(directory_path)
      quoted_path = quote_shell_argument(directory_path)

      case RbConfig::CONFIG['host_os']
      when /mswin|mingw|cygwin/
        # Windows
        system("explorer #{quoted_path}")
      when /darwin/
        # macOS
        system("open #{quoted_path}")
      else
        # Linux/Unix
        system("xdg-open #{quoted_path}")
      end
    rescue StandardError => e
      warn "Failed to open directory: #{e.message}"
      false
    end
  end
end

