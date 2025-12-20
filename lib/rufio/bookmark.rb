# frozen_string_literal: true

require 'json'
require 'fileutils'

module Rufio
  class Bookmark
    MAX_BOOKMARKS = 9

    def initialize(config_file = nil)
      @config_file = config_file || default_config_file
      @bookmarks = []
      ensure_config_directory
      load
    end

    def add(path, name)
      return false if @bookmarks.length >= MAX_BOOKMARKS
      return false if exists_by_name?(name)
      return false if exists_by_path?(path)
      return false unless Dir.exist?(path)

      @bookmarks << { path: File.expand_path(path), name: name }
      save
      true
    end

    def remove(name)
      initial_length = @bookmarks.length
      @bookmarks.reject! { |bookmark| bookmark[:name] == name }
      
      if @bookmarks.length < initial_length
        save
        true
      else
        false
      end
    end

    def get_path(name)
      bookmark = @bookmarks.find { |b| b[:name] == name }
      bookmark&.[](:path)
    end

    def find_by_number(number)
      return nil unless number.is_a?(Integer)
      return nil if number < 1 || number > @bookmarks.length

      sorted_bookmarks[number - 1]
    end

    def list
      sorted_bookmarks
    end

    def save
      begin
        File.write(@config_file, JSON.pretty_generate(@bookmarks))
        true
      rescue StandardError => e
        warn "Failed to save bookmarks: #{e.message}"
        false
      end
    end

    def load
      return true unless File.exist?(@config_file)

      begin
        content = File.read(@config_file)
        @bookmarks = JSON.parse(content, symbolize_names: true)
        @bookmarks = [] unless @bookmarks.is_a?(Array)
        
        # 無効なブックマークを除去
        @bookmarks = @bookmarks.select do |bookmark|
          bookmark.is_a?(Hash) &&
            bookmark.key?(:path) &&
            bookmark.key?(:name) &&
            bookmark[:path].is_a?(String) &&
            bookmark[:name].is_a?(String)
        end
        
        true
      rescue JSON::ParserError, StandardError => e
        warn "Failed to load bookmarks: #{e.message}"
        @bookmarks = []
        true
      end
    end

    private

    def default_config_file
      File.expand_path('~/.config/rufio/bookmarks.json')
    end

    def ensure_config_directory
      config_dir = File.dirname(@config_file)
      FileUtils.mkdir_p(config_dir) unless Dir.exist?(config_dir)
    end

    def exists_by_name?(name)
      @bookmarks.any? { |bookmark| bookmark[:name] == name }
    end

    def exists_by_path?(path)
      expanded_path = File.expand_path(path)
      @bookmarks.any? { |bookmark| bookmark[:path] == expanded_path }
    end

    def sorted_bookmarks
      @bookmarks.sort_by { |bookmark| bookmark[:name] }
    end
  end
end