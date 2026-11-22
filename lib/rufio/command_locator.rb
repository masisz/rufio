# frozen_string_literal: true

require 'rbconfig'

module Rufio
  # PATH 上にコマンドがあるかを調べる。
  # which を起動しないので、キー入力ごとに呼ばれても負荷にならず、which が無い
  # Windows でも動く（PATHEXT を見る）。
  module CommandLocator
    WINDOWS_DEFAULT_PATHEXT = '.COM;.EXE;.BAT;.CMD'

    class << self
      def available?(name)
        cache.fetch(name) { cache[name] = locate(name) }
      end

      def reset!
        @cache = {}
      end

      private

      def cache
        @cache ||= {}
      end

      def locate(name)
        return false if name.nil? || name.to_s.empty?
        return executable?(name) if name.to_s.include?(File::SEPARATOR)

        ENV.fetch('PATH', '').split(File::PATH_SEPARATOR).any? do |dir|
          next false if dir.empty?

          extensions.any? { |ext| executable?(File.join(dir, "#{name}#{ext}")) }
        end
      end

      def extensions
        return [''] unless RbConfig::CONFIG['host_os'] =~ /mswin|mingw|cygwin/

        (ENV['PATHEXT'] || WINDOWS_DEFAULT_PATHEXT).split(';')
      end

      def executable?(path)
        File.executable?(path) && !File.directory?(path)
      end
    end
  end
end
