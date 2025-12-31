# frozen_string_literal: true

require 'ffi'
require 'json'

module Rufio
  module Native
    module TextUtils
      extend FFI::Library

      class << self
        def library_path
          @library_path ||= begin
            ext = case RbConfig::CONFIG['host_os']
                  when /darwin/ then 'dylib'
                  when /linux/  then 'so'
                  when /mswin|mingw/ then 'dll'
                  end

            File.expand_path("../../native/libtextutils.#{ext}", __dir__)
          end
        end

        def available?
          @available ||= File.exist?(library_path)
        rescue StandardError
          false
        end

        def load_library!
          return false unless available?
          return true if @loaded

          ffi_lib library_path

          attach_function :DisplayWidth, [:string], :int
          attach_function :TruncateToWidth, [:string, :int], :string
          attach_function :WrapText, [:string, :int], :string
          attach_function :CalculateWidths, [:string], :string

          @loaded = true
        rescue FFI::NotFoundError, LoadError => e
          warn "⚠️  Failed to load native text utils: #{e.message}"
          @available = false
          false
        end

        def display_width(text)
          return nil unless available? && load_library!

          DisplayWidth(text.to_s)
        rescue FFI::NotFoundError
          nil
        end

        def truncate_to_width(text, max_width)
          return nil unless available? && load_library!

          TruncateToWidth(text.to_s, max_width.to_i)
        rescue FFI::NotFoundError
          nil
        end

        def wrap_text(text, max_width)
          return nil unless available? && load_library!

          result_json = WrapText(text.to_s, max_width.to_i)
          JSON.parse(result_json)
        rescue JSON::ParserError, FFI::NotFoundError
          nil
        end

        def calculate_widths(lines)
          return nil unless available? && load_library!

          lines_json = JSON.generate(lines)
          result_json = CalculateWidths(lines_json)
          JSON.parse(result_json)
        rescue JSON::ParserError, FFI::NotFoundError
          nil
        end
      end

      load_library!
    end
  end
end
