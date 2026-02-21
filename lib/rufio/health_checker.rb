# frozen_string_literal: true

require 'pastel'

module Rufio
  class HealthChecker
    def initialize
      @pastel = Pastel.new
      # Load configuration including language settings
      ConfigLoader.load_config
    end

    def run_check
      puts @pastel.bold(ConfigLoader.message('health.title'))
      puts "=" * 40
      puts

      checks = [
        { name: ConfigLoader.message('health.ruby_version'), method: :check_ruby_version },
        { name: ConfigLoader.message('health.required_gems'), method: :check_required_gems },
        { name: ConfigLoader.message('health.fzf'), method: :check_fzf },
        { name: ConfigLoader.message('health.rga'), method: :check_rga },
        { name: ConfigLoader.message('health.zoxide'), method: :check_zoxide },
        { name: ConfigLoader.message('health.bat'), method: :check_bat },
        { name: ConfigLoader.message('health.file_opener'), method: :check_file_opener }
      ]

      results = []
      checks.each do |check|
        result = send(check[:method])
        results << result
        print_check_result(check[:name], result)
      end

      puts
      print_summary(results)
      
      results.all? { |r| r[:status] == :ok }
    end

    private

    def check_ruby_version
      version = RUBY_VERSION
      major, minor = version.split('.').map(&:to_i)
      
      if major > 2 || (major == 2 && minor >= 7)
        {
          status: :ok,
          message: "Ruby #{version}",
          details: nil
        }
      else
        {
          status: :error,
          message: "Ruby #{version} (requires >= 2.7.0)",
          details: ConfigLoader.message('health.ruby_upgrade_needed')
        }
      end
    end

    def check_required_gems
      required_gems = %w[io-console pastel tty-cursor tty-screen]
      missing_gems = []

      required_gems.each do |gem_name|
        begin
          require gem_name.gsub('-', '/')
        rescue LoadError
          missing_gems << gem_name
        end
      end

      if missing_gems.empty?
        {
          status: :ok,
          message: ConfigLoader.message('health.all_gems_installed'),
          details: nil
        }
      else
        {
          status: :error,
          message: "#{ConfigLoader.message('health.missing_gems')}: #{missing_gems.join(', ')}",
          details: "#{ConfigLoader.message('health.gem_install_instruction')} #{missing_gems.join(' ')}"
        }
      end
    end

    def check_fzf
      if system("which fzf > /dev/null 2>&1")
        version = `fzf --version 2>/dev/null`.strip
        {
          status: :ok,
          message: "fzf #{version}",
          details: nil
        }
      else
        {
          status: :warning,
          message: "fzf #{ConfigLoader.message('health.tool_not_found')}",
          details: install_instruction_for('fzf')
        }
      end
    end

    def check_rga
      if system("which rga > /dev/null 2>&1")
        version = `rga --version 2>/dev/null | head -1`.strip
        {
          status: :ok,
          message: version,
          details: nil
        }
      else
        {
          status: :warning,
          message: "rga #{ConfigLoader.message('health.tool_not_found')}",
          details: install_instruction_for('rga')
        }
      end
    end

    def check_zoxide
      if system("which zoxide > /dev/null 2>&1")
        version = `zoxide --version 2>/dev/null`.strip
        {
          status: :ok,
          message: version,
          details: nil
        }
      else
        {
          status: :warning,
          message: "zoxide #{ConfigLoader.message('health.tool_not_found')}",
          details: install_instruction_for('zoxide')
        }
      end
    end

    def check_bat
      if system("which bat > /dev/null 2>&1")
        version = `bat --version 2>/dev/null`.strip
        {
          status: :ok,
          message: version,
          details: nil
        }
      else
        {
          status: :warning,
          message: "bat #{ConfigLoader.message('health.tool_not_found')}",
          details: install_instruction_for('bat')
        }
      end
    end

    def check_file_opener
      case RUBY_PLATFORM
      when /darwin/
        opener = "open"
        description = ConfigLoader.message('health.macos_opener')
      when /linux/
        opener = "xdg-open"
        description = ConfigLoader.message('health.linux_opener')
      when /mswin|mingw|cygwin/
        opener = "explorer"
        description = ConfigLoader.message('health.windows_opener')
      else
        return {
          status: :warning,
          message: "#{ConfigLoader.message('health.unknown_platform')}: #{RUBY_PLATFORM}",
          details: ConfigLoader.message('health.file_open_may_not_work')
        }
      end

      if system("which #{opener} > /dev/null 2>&1") || RUBY_PLATFORM =~ /mswin|mingw|cygwin/
        {
          status: :ok,
          message: description,
          details: nil
        }
      else
        {
          status: :warning,
          message: "#{opener} #{ConfigLoader.message('health.tool_not_found')}",
          details: ConfigLoader.message('health.file_open_may_not_work')
        }
      end
    end

    def install_instruction_for(tool)
      case RUBY_PLATFORM
      when /darwin/
        case tool
        when 'fzf'
          "#{ConfigLoader.message('health.install_brew')} fzf"
        when 'rga'
          "#{ConfigLoader.message('health.install_brew')} rga"
        when 'zoxide'
          "#{ConfigLoader.message('health.install_brew')} zoxide"
        when 'bat'
          "#{ConfigLoader.message('health.install_brew')} bat  # optional: syntax highlight"
        end
      when /linux/
        case tool
        when 'fzf'
          "#{ConfigLoader.message('health.install_apt')} fzf (Ubuntu/Debian) or check your package manager"
        when 'rga'
          ConfigLoader.message('health.rga_releases')
        when 'zoxide'
          "#{ConfigLoader.message('health.install_apt')} zoxide (Ubuntu/Debian) or check your package manager"
        when 'bat'
          "#{ConfigLoader.message('health.install_apt')} bat (Ubuntu/Debian) or check your package manager  # optional: syntax highlight"
        end
      else
        ConfigLoader.message('health.install_guide')
      end
    end

    def print_check_result(name, result)
      status_icon = case result[:status]
                   when :ok
                     @pastel.green("✓")
                   when :warning
                     @pastel.yellow("⚠")
                   when :error
                     @pastel.red("✗")
                   end

      status_color = case result[:status]
                    when :ok
                      :green
                    when :warning
                      :yellow
                    when :error
                      :red
                    end

      puts "#{status_icon} #{name.ljust(20)} #{@pastel.decorate(result[:message], status_color)}"
      
      if result[:details]
        puts "  #{@pastel.dim(result[:details])}"
      end
    end

    def print_summary(results)
      ok_count = results.count { |r| r[:status] == :ok }
      warning_count = results.count { |r| r[:status] == :warning }
      error_count = results.count { |r| r[:status] == :error }

      puts "#{ConfigLoader.message('health.summary')}"
      puts "  #{@pastel.green("✓ #{ok_count} #{ConfigLoader.message('health.ok')}")}"
      puts "  #{@pastel.yellow("⚠ #{warning_count} #{ConfigLoader.message('health.warnings')}")}}" if warning_count > 0
      puts "  #{@pastel.red("✗ #{error_count} #{ConfigLoader.message('health.errors')}")}}" if error_count > 0

      if error_count > 0
        puts
        puts @pastel.red(ConfigLoader.message('health.critical_missing'))
      elsif warning_count > 0
        puts
        puts @pastel.yellow(ConfigLoader.message('health.optional_missing'))
      else
        puts
        puts @pastel.green(ConfigLoader.message('health.all_passed'))
      end
    end
  end
end