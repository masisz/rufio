# frozen_string_literal: true

require_relative 'file_opener'
require_relative 'filter_manager'

module Rufio
  # ナビゲーション専用コントローラ
  # KeybindHandler から移動・フィルタ・プレビュースクロール系メソッドを分離し、単一責任原則に準拠
  class NavigationController
    attr_reader :current_index, :preview_scroll_offset

    def initialize(directory_listing, filter_manager)
      @directory_listing = directory_listing
      @filter_manager = filter_manager
      @current_index = 0
      @preview_focused = false
      @preview_scroll_offset = 0
      @file_opener = FileOpener.new
      @terminal_ui = nil
    end

    def set_terminal_ui(terminal_ui)
      @terminal_ui = terminal_ui
    end

    def set_directory_listing(directory_listing)
      @directory_listing = directory_listing
      @current_index = 0
    end

    def select_index(index)
      @current_index = index
    end

    # ============================
    # 移動メソッド
    # ============================

    def move_down(entries)
      @current_index = [@current_index + 1, entries.length - 1].min
      reset_preview_scroll
      true
    end

    def move_up
      @current_index = [@current_index - 1, 0].max
      reset_preview_scroll
      true
    end

    def move_to_top
      @current_index = 0
      true
    end

    def move_to_bottom(entries)
      @current_index = [entries.length - 1, 0].max
      true
    end

    # ============================
    # ディレクトリナビゲーション
    # ============================

    # エントリに対してEnterキーの動作を実行
    # @param entry [Hash] 対象エントリ
    # @param in_help_mode [Boolean] ヘルプモード中かどうか
    # @param in_log_viewer_mode [Boolean] ログビューワモード中かどうか
    def navigate_enter(entry, in_help_mode, in_log_viewer_mode)
      return false unless entry

      if entry[:type] == 'directory'
        return false if in_help_mode || in_log_viewer_mode

        result = @directory_listing.navigate_to(entry[:name])
        if result
          @current_index = 0
          clear_filter_mode
        end
        result
      else
        false
      end
    end

    def navigate_parent
      return false unless @directory_listing

      result = @directory_listing.navigate_to_parent
      if result
        @current_index = 0
        clear_filter_mode
      end
      result
    end

    def refresh
      @terminal_ui&.refresh_display
      return false unless @directory_listing

      @directory_listing.refresh
      if @filter_manager.filter_active?
        @filter_manager.update_entries(@directory_listing.list_entries)
      else
        entries = @directory_listing.list_entries
        @current_index = [@current_index, entries.length - 1].min if entries.any?
      end
      true
    end

    def open_current_file(entry)
      return false unless entry

      if entry[:type] == 'file'
        @file_opener.open_file(entry[:path])
        :needs_refresh
      else
        false
      end
    end

    def open_directory_in_explorer
      current_path = @directory_listing&.current_path || Dir.pwd
      @file_opener.open_directory_in_explorer(current_path)
      true
    end

    # ============================
    # フィルタ
    # ============================

    def start_filter_mode
      @filter_manager.start_filter_mode(@directory_listing.list_entries)
      @current_index = 0
      true
    end

    def handle_filter_input(key)
      result = @filter_manager.handle_filter_input(key)

      case result
      when :exit_clear
        clear_filter_mode
      when :exit_keep
        exit_filter_mode_keep_filter
      when :backspace_exit
        clear_filter_mode
      when :continue
        @current_index = [@current_index, [@filter_manager.filtered_entries.length - 1, 0].max].min
      end

      true
    end

    def exit_filter_mode_keep_filter
      @filter_manager.exit_filter_mode_keep_filter
    end

    def clear_filter_mode
      @filter_manager.clear_filter
      @current_index = 0
    end

    # 後方互換用エイリアス
    def exit_filter_mode
      clear_filter_mode
    end

    # ============================
    # プレビューペインフォーカス
    # ============================

    def preview_focused?
      @preview_focused
    end

    # @param entry [Hash] 現在選択中のエントリ
    def focus_preview_pane(entry)
      return false unless entry
      return false unless entry[:type] == 'file'

      @preview_focused = true
      @preview_scroll_offset = 0
      true
    end

    def unfocus_preview_pane
      return false unless @preview_focused

      @preview_focused = false
      true
    end

    # ============================
    # プレビュースクロール
    # ============================

    def scroll_preview_down
      return false unless @preview_focused

      @preview_scroll_offset += 1
      true
    end

    def scroll_preview_up
      return false unless @preview_focused

      @preview_scroll_offset = [@preview_scroll_offset - 1, 0].max
      true
    end

    def scroll_preview_page_down
      return false unless @preview_focused

      @preview_scroll_offset += 20
      true
    end

    def scroll_preview_page_up
      return false unless @preview_focused

      @preview_scroll_offset = [@preview_scroll_offset - 20, 0].max
      true
    end

    def reset_preview_scroll
      @preview_scroll_offset = 0
    end

    # ============================
    # キー処理
    # ============================

    # プレビューペインフォーカス中のキー処理
    def handle_preview_focus_key(key)
      case key
      when 'j', "\e[B"  # j or Down arrow
        scroll_preview_down
      when 'k', "\e[A"  # k or Up arrow
        scroll_preview_up
      when "\x04"  # Ctrl+D
        scroll_preview_page_down
      when "\x15"  # Ctrl+U
        scroll_preview_page_up
      when "\e"   # ESC
        unfocus_preview_pane
      else
        false
      end
    end

    # Enterキーの処理：ファイルならプレビューフォーカス、ディレクトリならナビゲート
    # @param entry [Hash] 現在選択中のエントリ
    # @param in_help_mode [Boolean]
    # @param in_log_viewer_mode [Boolean]
    def handle_enter_key(entry, in_help_mode, in_log_viewer_mode)
      return false unless entry

      if entry[:type] == 'file'
        focus_preview_pane(entry)
      else
        navigate_enter(entry, in_help_mode, in_log_viewer_mode)
      end
    end
  end
end
