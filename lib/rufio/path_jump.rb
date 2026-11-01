# frozen_string_literal: true

require 'uri'

module Rufio
  # :cd に貼り付けられたパスを移動先に解決する。
  # 引用符・末尾の改行・バックスラッシュエスケープされた空白・file:// URL を受け付け、
  # ファイルを指す場合はその親ディレクトリとファイル自体を返す。
  module PathJump
    QUOTE_PAIRS = [%w[' '], %w[" "]].freeze

    class << self
      # @param input [String] 貼り付けられたパス（空なら ホーム）
      # @param base_dir [String] 相対パスの基準ディレクトリ
      # @return [Hash] { directory:, file: } または { directory: nil, error: }
      def resolve(input, base_dir)
        path = normalize(input.to_s)
        path = '~' if path.empty?
        expanded = File.expand_path(path, base_dir)

        if File.directory?(expanded)
          { directory: expanded, file: nil }
        elsif File.file?(expanded)
          { directory: File.dirname(expanded), file: expanded }
        else
          { directory: nil, error: "Path not found: #{path}" }
        end
      rescue ArgumentError => e
        { directory: nil, error: "Invalid path: #{e.message}" }
      end

      private

      def normalize(text)
        path = text.strip
        QUOTE_PAIRS.each do |open, close|
          if path.length >= 2 && path.start_with?(open) && path.end_with?(close)
            path = path[1..-2]
            break
          end
        end
        path = from_file_url(path) if path.start_with?('file://')
        path = path.gsub(/\\(.)/, '\1') unless Gem.win_platform?
        path
      end

      def from_file_url(url)
        uri = URI.parse(url)
        URI.decode_www_form_component(uri.path.to_s.gsub('+', '%2B'))
      rescue URI::InvalidURIError
        url.delete_prefix('file://')
      end
    end
  end
end
