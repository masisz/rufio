# frozen_string_literal: true

module Rufio
  # プロジェクトモード - ブックマークしたプロジェクトの管理とコマンド実行
  class ProjectMode
    attr_reader :selected_path, :selected_name

    def initialize(bookmark, log_dir)
      @bookmark = bookmark
      @log_dir = log_dir
      @active = false
      @selected_path = nil
      @selected_name = nil
    end

    # プロジェクトモードをアクティブにする
    def activate
      @active = true
    end

    # プロジェクトモードを非アクティブにする
    def deactivate
      @active = false
      @selected_path = nil
      @selected_name = nil
    end

    # プロジェクトモードがアクティブかどうか
    def active?
      @active
    end

    # ブックマーク一覧を取得
    def list_bookmarks
      return [] unless @active

      @bookmark.list
    end

    # ブックマークを番号で選択
    def select_bookmark(number)
      return false unless @active

      bookmark = @bookmark.find_by_number(number)
      return false unless bookmark

      @selected_path = bookmark[:path]
      @selected_name = bookmark[:name]
      true
    end

    # 選択をクリア
    def clear_selection
      @selected_path = nil
      @selected_name = nil
    end
  end
end
