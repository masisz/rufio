# frozen_string_literal: true

# Rufio プラグイン実装例
# このファイルを ~/.rufio/plugins/ にコピーして使用してください

module Rufio
  module Plugins
    # ファイル検索プラグインの例
    class FileSearchPlugin < Plugin
      def name
        "FileSearch"
      end

      def description
        "ファイル名で検索する機能"
      end

      def version
        "1.0.0"
      end

      def commands
        {
          search: method(:search_files),
          find_by_ext: method(:find_by_extension)
        }
      end

      private

      # ファイル名で検索
      def search_files(query)
        Dir.glob("**/*#{query}*").each do |file|
          puts file
        end
      end

      # 拡張子でファイルを検索
      def find_by_extension(ext)
        Dir.glob("**/*.#{ext}").each do |file|
          puts file
        end
      end
    end

    # Git統合プラグインの例（外部gem依存）
    class GitIntegrationPlugin < Plugin
      # gitコマンドが必要
      # requires 'git' # gemが必要な場合

      def name
        "GitIntegration"
      end

      def description
        "Git操作を統合"
      end

      def commands
        {
          git_status: method(:show_git_status),
          git_branch: method(:show_current_branch)
        }
      end

      private

      def show_git_status
        if system('which git > /dev/null 2>&1')
          system('git status')
        else
          puts "⚠️  gitがインストールされていません"
        end
      end

      def show_current_branch
        if system('which git > /dev/null 2>&1')
          branch = `git branch --show-current`.strip
          puts "現在のブランチ: #{branch}"
        else
          puts "⚠️  gitがインストールされていません"
        end
      end
    end

    # シンプルなユーティリティプラグイン
    class UtilityPlugin < Plugin
      def name
        "Utility"
      end

      def description
        "便利なユーティリティ機能"
      end

      def commands
        {
          disk_usage: method(:show_disk_usage),
          count_files: method(:count_files_in_directory)
        }
      end

      private

      def show_disk_usage
        puts "ディスク使用量:"
        system('df -h .')
      end

      def count_files_in_directory
        files = Dir.glob('*').select { |f| File.file?(f) }
        dirs = Dir.glob('*').select { |f| File.directory?(f) }

        puts "ファイル数: #{files.count}"
        puts "ディレクトリ数: #{dirs.count}"
      end
    end
  end
end
