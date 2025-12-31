# frozen_string_literal: true

require 'ffi'
require 'json'

module Rufio
  module Native
    module Preview
      extend FFI::Library

      class << self
        def library_path
          @library_path ||= begin
            ext = case RbConfig::CONFIG['host_os']
                  when /darwin/ then 'dylib'
                  when /linux/  then 'so'
                  when /mswin|mingw/ then 'dll'
                  end

            File.expand_path("../../native/libpreview.#{ext}", __dir__)
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

          attach_function :GeneratePreview, [:string, :int], :string
          attach_function :IsBinaryFile, [:string], :int

          @loaded = true
        rescue FFI::NotFoundError, LoadError => e
          warn "⚠️  Failed to load native preview: #{e.message}"
          @available = false
          false
        end

        def generate(path, max_lines: 50)
          return nil unless available? && load_library!

          result_json = GeneratePreview(path.to_s, max_lines.to_i)
          JSON.parse(result_json, symbolize_names: true)
        rescue JSON::ParserError, FFI::NotFoundError => e
          { error: e.message }
        end

        def binary?(path)
          return nil unless available? && load_library!

          IsBinaryFile(path.to_s) == 1
        rescue FFI::NotFoundError
          nil
        end
      end

      load_library!
    end
  end
end
