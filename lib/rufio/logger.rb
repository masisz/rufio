# frozen_string_literal: true

module Rufio
  # Unified logger for debug and error messages
  # Only logs when BENIYA_DEBUG environment variable is set to '1'
  class Logger
    LOG_FILE = File.join(Dir.home, '.rufio_debug.log')

    # Log levels
    DEBUG = :debug
    INFO = :info
    WARN = :warn
    ERROR = :error

    class << self
      # Log a debug message with optional context
      # @param message [String] The log message
      # @param context [Hash] Additional context information
      def debug(message, context: {})
        return unless debug_enabled?

        write_log(DEBUG, message, context)
      end

      # Log an info message
      # @param message [String] The log message
      # @param context [Hash] Additional context information
      def info(message, context: {})
        return unless debug_enabled?

        write_log(INFO, message, context)
      end

      # Log a warning message
      # @param message [String] The log message
      # @param context [Hash] Additional context information
      def warn(message, context: {})
        return unless debug_enabled?

        write_log(WARN, message, context)
      end

      # Log an error message with optional exception
      # @param message [String] The error message
      # @param exception [Exception, nil] Optional exception object
      # @param context [Hash] Additional context information
      def error(message, exception: nil, context: {})
        return unless debug_enabled?

        full_context = context.dup
        if exception
          full_context[:exception] = exception.message
          full_context[:backtrace] = exception.backtrace&.first(5)
        end

        write_log(ERROR, message, full_context)
      end

      # Clear the log file
      def clear_log
        return unless debug_enabled?

        File.open(LOG_FILE, 'w') { |f| f.puts "=== Rufio Debug Log Cleared at #{Time.now} ===" }
      end

      private

      # Check if debug logging is enabled
      # @return [Boolean]
      def debug_enabled?
        ENV['BENIYA_DEBUG'] == '1'
      end

      # Write a log entry to the log file
      # @param level [Symbol] Log level
      # @param message [String] Log message
      # @param context [Hash] Context information
      def write_log(level, message, context)
        File.open(LOG_FILE, 'a') do |f|
          timestamp = Time.now.strftime('%Y-%m-%d %H:%M:%S')
          f.puts "[#{timestamp}] [#{level.to_s.upcase}] #{message}"

          unless context.empty?
            f.puts '  Context:'
            context.each do |key, value|
              if value.is_a?(Array) && value.length > 10
                f.puts "    #{key}: [#{value.length} items]"
              else
                f.puts "    #{key}: #{value.inspect}"
              end
            end
          end

          f.puts ''
        end
      rescue StandardError => e
        # Silently fail if we can't write to log file
        # Don't want logging to break the application
        warn "Failed to write to log file: #{e.message}"
      end
    end
  end
end
