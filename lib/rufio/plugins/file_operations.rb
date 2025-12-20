# frozen_string_literal: true

module Rufio
  module Plugins
    # 基本的なファイル操作を提供するプラグイン
    class FileOperations < Plugin
      def name
        "FileOperations"
      end

      def description
        "基本的なファイル操作(コピー、移動、削除)"
      end

      def commands
        {
          copy: method(:copy),
          move: method(:move),
          delete: method(:delete)
        }
      end

      private

      # ファイルコピー（スタブ実装）
      def copy
        # 実装は将来追加
        nil
      end

      # ファイル移動（スタブ実装）
      def move
        # 実装は将来追加
        nil
      end

      # ファイル削除（スタブ実装）
      def delete
        # 実装は将来追加
        nil
      end
    end
  end
end
