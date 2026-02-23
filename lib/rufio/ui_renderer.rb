# frozen_string_literal: true

require_relative 'text_utils'

module Rufio
  # UIレンダリング専用クラス
  # TerminalUI から draw_*_to_buffer 系メソッドを分離し、単一責任原則に準拠
  # - ディレクトリリスト・ファイルプレビュー・フッター・タブ描画を担当
  # - キャッシュ（プレビュー・ブックマーク）を管理
  # - シンタックスハイライト（bat 連携）を担当
  class UIRenderer
    # Layout constants
    HEADER_FOOTER_MARGIN = 2       # Header(1行) + Footer(1行) 分のマージン
    CONTENT_START_LINE = 1         # コンテンツ開始行（フッタ1行: Y=0）
    CURSOR_OFFSET = 1              # カーソル位置のオフセット
    ICON_SIZE_PADDING = 12         # アイコン、選択マーク、サイズ情報分
    BOOKMARK_HIGHLIGHT_DURATION = 0.5  # ブックマークハイライト表示時間（秒）
    TAB_SEPARATOR = ">"            # タブ間セパレータ

    # File display constants
    KILOBYTE = 1024
    MEGABYTE = KILOBYTE * 1024
    GIGABYTE = MEGABYTE * 1024

    attr_accessor :keybind_handler, :directory_listing, :file_preview
    attr_accessor :background_executor, :test_mode
    attr_accessor :completion_lamp_message, :completion_lamp_time
    attr_reader :tab_mode_manager, :highlight_updated

    def initialize(screen_width:, screen_height:,
                   keybind_handler: nil, directory_listing: nil,
                   file_preview: nil, background_executor: nil,
                   test_mode: false, left_panel_ratio: 0.5)
      @screen_width = screen_width
      @screen_height = screen_height
      @keybind_handler = keybind_handler
      @directory_listing = directory_listing
      @file_preview = file_preview
      @background_executor = background_executor
      @test_mode = test_mode
      @left_panel_ratio = left_panel_ratio

      # Preview cache
      @preview_cache = {}
      @last_preview_path = nil

      # Syntax highlighter（bat が利用可能な場合のみ動作）
      @syntax_highlighter = SyntaxHighlighter.new
      @highlight_updated = false

      # Bookmark cache（毎フレームのファイルI/Oを回避）
      @cached_bookmarks = nil
      @cached_bookmark_time = nil
      @bookmark_cache_ttl = 1.0

      # Bookmark highlight (Tab ジャンプ時に 500ms ハイライト)
      @highlighted_bookmark_index = nil
      @highlighted_bookmark_time = nil

      # Completion lamp
      @completion_lamp_message = nil
      @completion_lamp_time = nil

      # Tab mode manager
      @tab_mode_manager = TabModeManager.new
    end

    # ============================
    # Cache management
    # ============================

    def clear_preview_cache
      @preview_cache.clear
      @last_preview_path = nil
    end

    def clear_bookmark_cache
      @cached_bookmarks = nil
      @cached_bookmark_time = nil
    end

    def highlight_updated?
      @highlight_updated
    end

    def reset_highlight_updated
      @highlight_updated = false
    end

    def set_highlighted_bookmark(index)
      @highlighted_bookmark_index = index
      @highlighted_bookmark_time = Time.now
    end

    def clear_highlighted_bookmark
      @highlighted_bookmark_index = nil
      @highlighted_bookmark_time = nil
    end

    # ブックマークハイライトが期限切れかどうか
    def bookmark_highlight_expired?
      return false unless @highlighted_bookmark_index && @highlighted_bookmark_time

      (Time.now - @highlighted_bookmark_time) >= BOOKMARK_HIGHLIGHT_DURATION
    end

    # ============================
    # 全体描画エントリーポイント
    # ============================

    # Screen バッファに全体を描画する
    # @param screen [Screen] 描画対象のスクリーンバッファ
    # @param notification_message [String, nil] 通知メッセージ
    # @param fps [Float, nil] FPS（テストモード時のみ表示）
    # @param in_job_mode [Boolean] ジョブモード中かどうか
    # @param job_manager [JobManager, nil] ジョブマネージャー
    # @param job_mode_instance [JobMode, nil] ジョブモードインスタンス
    def draw_screen(screen, notification_message: nil, fps: nil,
                    in_job_mode: false, job_manager: nil, job_mode_instance: nil)
      content_height = @screen_height - HEADER_FOOTER_MARGIN

      if in_job_mode
        # ジョブモード: フッタ y=0（上部）、コンテンツ y=1〜h-2、統合行 y=h-1（下部）
        draw_job_footer_to_buffer(screen, 0, job_manager)
        draw_job_list_to_buffer(screen, content_height, job_manager, job_mode_instance)
        draw_mode_tabs_to_buffer(screen, @screen_height - 1)
      else
        # 通常モード: フッタ y=0（上部）、コンテンツ y=1〜h-2、統合行 y=h-1（下部）
        draw_footer_to_buffer(screen, 0, fps)

        entries = get_display_entries
        selected_entry = entries[@keybind_handler.current_index]

        left_width = (@screen_width * @left_panel_ratio).to_i
        right_width = @screen_width - left_width

        draw_directory_list_to_buffer(screen, entries, left_width, content_height)
        draw_file_preview_to_buffer(screen, selected_entry, right_width, content_height, left_width)

        draw_mode_tabs_to_buffer(screen, @screen_height - 1)
      end

      # 通知メッセージがある場合は表示
      if notification_message
        notification_line = @screen_height - 1
        message_display = " #{notification_message} "
        message_display = message_display[0...(@screen_width - 3)] + "..." if message_display.length > @screen_width
        screen.put_string(0, notification_line, message_display.ljust(@screen_width), fg: "\e[7m")
      end
    end

    # 後方互換性のためのエイリアス（TerminalUI のシグネチャに合わせる）
    def draw_screen_to_buffer(screen, notification_message = nil, fps = nil,
                              in_job_mode: false, job_manager: nil, job_mode_instance: nil)
      draw_screen(screen,
                  notification_message: notification_message,
                  fps: fps,
                  in_job_mode: in_job_mode,
                  job_manager: job_manager,
                  job_mode_instance: job_mode_instance)
    end

    # ============================
    # ファイルサイズ表示
    # ============================

    def format_size(size)
      return '      ' if size == 0

      if size < KILOBYTE
        "#{size}B".rjust(6)
      elsif size < MEGABYTE
        "#{(size / KILOBYTE.to_f).round(1)}K".rjust(6)
      elsif size < GIGABYTE
        "#{(size / MEGABYTE.to_f).round(1)}M".rjust(6)
      else
        "#{(size / GIGABYTE.to_f).round(1)}G".rjust(6)
      end
    end

    # ============================
    # エントリ表示情報
    # ============================

    def get_entry_display_info(entry)
      colors = ConfigLoader.colors

      case entry[:type]
      when 'directory'
        color_code = ColorHelper.color_to_ansi(colors[:directory])
        ['📁', color_code]
      when 'executable'
        color_code = ColorHelper.color_to_ansi(colors[:executable])
        ['⚡', color_code]
      else
        case File.extname(entry[:name]).downcase
        when '.rb'
          ['💎', "\e[31m"]  # 赤
        when '.js', '.ts'
          ['📜', "\e[33m"]  # 黄
        when '.txt', '.md'
          color_code = ColorHelper.color_to_ansi(colors[:file])
          ['📄', color_code]
        else
          color_code = ColorHelper.color_to_ansi(colors[:file])
          ['📄', color_code]
        end
      end
    end

    # ============================
    # プレビュー行抽出
    # ============================

    # FilePreview の結果ハッシュからプレーンテキスト行を抽出する
    def extract_preview_lines(preview)
      case preview[:type]
      when 'text', 'code'
        preview[:lines]
      when 'binary'
        ["(#{ConfigLoader.message('file.binary_file')})", ConfigLoader.message('file.cannot_preview')]
      when 'error'
        ["#{ConfigLoader.message('file.error_prefix')}:", preview[:message]]
      else
        ["(#{ConfigLoader.message('file.cannot_preview')})"]
      end
    rescue StandardError
      ["(#{ConfigLoader.message('file.preview_error')})"]
    end

    # ============================
    # ディレクトリリスト描画
    # ============================

    def draw_directory_list_to_buffer(screen, entries, width, height)
      start_index = [@keybind_handler.current_index - height / 2, 0].max

      (0...height).each do |i|
        entry_index = start_index + i
        line_num = i + CONTENT_START_LINE

        if entry_index < entries.length
          entry = entries[entry_index]
          is_selected = entry_index == @keybind_handler.current_index

          draw_entry_line_to_buffer(screen, entry, width, is_selected, 0, line_num)
        else
          # 空行
          safe_width = [width - CURSOR_OFFSET, (@screen_width * @left_panel_ratio).to_i - CURSOR_OFFSET].min
          screen.put_string(0, line_num, ' ' * safe_width)
        end
      end
    end

    def draw_entry_line_to_buffer(screen, entry, width, is_selected, x, y)
      # アイコンと色の設定
      icon, color = get_entry_display_info(entry)

      # 左ペイン専用の安全な幅を計算
      safe_width = [width - CURSOR_OFFSET, (@screen_width * @left_panel_ratio).to_i - CURSOR_OFFSET].min

      # 選択マークの追加
      selection_mark = @keybind_handler.is_selected?(entry[:name]) ? "✓ " : "  "

      # ファイル名（必要に応じて切り詰め）
      name = entry[:name]
      max_name_length = safe_width - ICON_SIZE_PADDING
      name = name[0...max_name_length - 3] + '...' if max_name_length > 0 && name.length > max_name_length

      # サイズ情報
      size_info = format_size(entry[:size])

      # 行の内容を構築
      content_without_size = "#{selection_mark}#{icon} #{name}"
      available_for_content = safe_width - size_info.length

      line_content = if available_for_content > 0
                       content_without_size.ljust(available_for_content) + size_info
                     else
                       content_without_size
                     end

      # 確実に safe_width を超えないよう切り詰め
      line_content = line_content[0...safe_width]

      # 色を決定
      if is_selected
        fg_color = ColorHelper.color_to_selected_ansi(ConfigLoader.colors[:selected])
        screen.put_string(x, y, line_content, fg: fg_color)
      elsif @keybind_handler.is_selected?(entry[:name])
        # 選択されたアイテムは緑背景、黒文字
        screen.put_string(x, y, line_content, fg: "\e[42m\e[30m")
      else
        screen.put_string(x, y, line_content, fg: color)
      end
    end

    # ============================
    # ファイルプレビュー描画
    # ============================

    def draw_file_preview_to_buffer(screen, selected_entry, width, height, left_offset)
      # 事前計算
      cursor_position = left_offset + CURSOR_OFFSET
      max_chars_from_cursor = @screen_width - cursor_position
      safe_width = [max_chars_from_cursor - 2, width - 2, 0].max

      # プレビューコンテンツをキャッシュから取得
      preview_content = nil
      wrapped_lines = nil
      highlighted_wrapped_lines = nil

      if selected_entry && selected_entry[:type] == 'file'
        if @last_preview_path != selected_entry[:path]
          full_preview = @file_preview.preview_file(selected_entry[:path])
          preview_content = extract_preview_lines(full_preview)
          @preview_cache[selected_entry[:path]] = {
            content: preview_content,
            preview_data: full_preview,
            highlighted: nil,
            wrapped: {},
            highlighted_wrapped: {}
          }
          @last_preview_path = selected_entry[:path]
        else
          cache_entry = @preview_cache[selected_entry[:path]]
          preview_content = cache_entry[:content] if cache_entry
        end

        # bat が利用可能な場合はシンタックスハイライトを取得（非同期）
        if @syntax_highlighter&.available? && preview_content
          cache_entry = @preview_cache[selected_entry[:path]]
          if cache_entry
            preview_data = cache_entry[:preview_data]
            if preview_data && preview_data[:type] == 'code' && preview_data[:encoding] == 'UTF-8'
              if cache_entry[:highlighted].nil?
                cache_entry[:highlighted] = false
                file_path = selected_entry[:path]
                @syntax_highlighter.highlight_async(file_path) do |lines|
                  if (ce = @preview_cache[file_path])
                    ce[:highlighted] = lines
                    ce[:highlighted_wrapped] = {}
                  end
                  @highlight_updated = true
                end
              end

              highlighted = cache_entry[:highlighted]
              if highlighted.is_a?(Array) && !highlighted.empty? && safe_width > 0
                if cache_entry[:highlighted_wrapped][safe_width]
                  highlighted_wrapped_lines = cache_entry[:highlighted_wrapped][safe_width]
                else
                  hl_wrapped = highlighted.flat_map do |hl_line|
                    tokens = AnsiLineParser.parse(hl_line)
                    tokens.empty? ? [[]] : AnsiLineParser.wrap(tokens, safe_width - 1)
                  end
                  cache_entry[:highlighted_wrapped][safe_width] = hl_wrapped
                  highlighted_wrapped_lines = hl_wrapped
                end
              end
            end
          end
        end

        # プレーンテキストの折り返し（ハイライトなしのフォールバック）
        if preview_content && safe_width > 0 && highlighted_wrapped_lines.nil?
          cache_entry = @preview_cache[selected_entry[:path]]
          if cache_entry && cache_entry[:wrapped][safe_width]
            wrapped_lines = cache_entry[:wrapped][safe_width]
          else
            wrapped_lines = TextUtils.wrap_preview_lines(preview_content, safe_width - 1)
            cache_entry[:wrapped][safe_width] = wrapped_lines if cache_entry
          end
        end
      end

      content_x = cursor_position + 1

      (0...height).each do |i|
        line_num = i + CONTENT_START_LINE

        # 区切り線
        screen.put(cursor_position, line_num, '│')

        next if safe_width <= 0

        if selected_entry && i == 0
          # プレビューヘッダー
          header = " #{selected_entry[:name]} "
          header += "[PREVIEW MODE]" if @keybind_handler&.preview_focused?
          header = TextUtils.truncate_to_width(header, safe_width) if TextUtils.display_width(header) > safe_width
          remaining_space = safe_width - TextUtils.display_width(header)
          header += ' ' * remaining_space if remaining_space > 0
          screen.put_string(content_x, line_num, header)

        elsif i >= 2 && highlighted_wrapped_lines
          # シンタックスハイライト付きコンテンツ
          scroll_offset = @keybind_handler&.preview_scroll_offset || 0
          display_line_index = i - 2 + scroll_offset

          if display_line_index < highlighted_wrapped_lines.length
            draw_highlighted_line_to_buffer(screen, content_x, line_num,
                                            highlighted_wrapped_lines[display_line_index], safe_width)
          else
            screen.put_string(content_x, line_num, ' ' * safe_width)
          end

        elsif i >= 2 && wrapped_lines
          # プレーンテキストコンテンツ
          scroll_offset = @keybind_handler&.preview_scroll_offset || 0
          display_line_index = i - 2 + scroll_offset

          content_to_print = if display_line_index < wrapped_lines.length
                               " #{wrapped_lines[display_line_index] || ''}"
                             else
                               ' '
                             end
          content_to_print = TextUtils.truncate_to_width(content_to_print, safe_width) if TextUtils.display_width(content_to_print) > safe_width
          remaining_space = safe_width - TextUtils.display_width(content_to_print)
          content_to_print += ' ' * remaining_space if remaining_space > 0
          screen.put_string(content_x, line_num, content_to_print)

        else
          screen.put_string(content_x, line_num, ' ' * safe_width)
        end
      end
    end

    # ハイライト済みトークン列を1行分 Screen バッファに描画する
    def draw_highlighted_line_to_buffer(screen, x, y, tokens, max_width)
      current_x = x
      max_x = x + max_width

      # 先頭スペース
      if current_x < max_x
        screen.put(current_x, y, ' ')
        current_x += 1
      end

      # トークンを描画
      tokens&.each do |token|
        break if current_x >= max_x
        token[:text].each_char do |char|
          char_w = TextUtils.char_width(char)
          break if current_x + char_w > max_x
          screen.put(current_x, y, char, fg: token[:fg])
          current_x += char_w
        end
      end

      # 残りをスペースで埋める
      while current_x < max_x
        screen.put(current_x, y, ' ')
        current_x += 1
      end
    end

    # ============================
    # フッター描画
    # ============================

    def draw_footer_to_buffer(screen, y, fps = nil)
      if @keybind_handler.filter_active?
        if @keybind_handler.instance_variable_get(:@filter_mode)
          help_text = "Filter mode: Type to filter, ESC to clear, Enter to apply, Backspace to delete"
        else
          help_text = "Filtered view active - Space to edit filter, ESC to clear filter"
        end
        footer_content = help_text.ljust(@screen_width)[0...@screen_width]
        screen.put_string(0, y, footer_content, fg: "\e[7m")
      else
        # ブックマークをキャッシュ（毎フレームのファイルI/Oを回避）
        current_time = Time.now
        if @cached_bookmarks.nil? || @cached_bookmark_time.nil? || (current_time - @cached_bookmark_time) > @bookmark_cache_ttl
          require_relative 'bookmark'
          bookmark = Bookmark.new
          @cached_bookmarks = bookmark.list
          @cached_bookmark_time = current_time
        end
        bookmarks = @cached_bookmarks

        # 起動ディレクトリを取得
        start_dir = @directory_listing&.start_directory
        start_dir_name = if start_dir
                           File.basename(start_dir)
                         else
                           "start"
                         end

        # ブックマーク一覧を作成（0.起動dir を先頭に追加）
        bookmark_parts = ["0.#{start_dir_name}"]
        unless bookmarks.empty?
          bookmark_parts.concat(bookmarks.take(9).map.with_index(1) { |bm, idx| "#{idx}.#{bm[:name]}" })
        end
        bookmark_text = bookmark_parts.join(" │ ")

        # 右側の情報
        right_parts = []

        # ジョブ数を表示（ジョブがある場合のみ）
        if @keybind_handler.has_jobs?
          job_text = @keybind_handler.job_status_bar_text
          right_parts << "[#{job_text}]" if job_text
        end

        # バックグラウンドコマンドの実行状態をランプで表示
        if @background_executor
          if @background_executor.running?
            command_name = @background_executor.current_command || "処理中"
            right_parts << "\e[32m🔄\e[0m #{command_name}"
          elsif @completion_lamp_message && @completion_lamp_time
            if (Time.now - @completion_lamp_time) < 3.0
              right_parts << @completion_lamp_message
            else
              @completion_lamp_message = nil
              @completion_lamp_time = nil
            end
          end
        end

        # FPS表示（test modeの時のみ）
        right_parts << "#{fps.round(1)} FPS" if @test_mode && fps

        right_info = right_parts.join(" | ")

        # ブックマーク一覧を利用可能な幅に収める
        if right_info.empty?
          available_width = @screen_width
        else
          available_width = @screen_width - right_info.length - 3
        end
        if bookmark_text.length > available_width && available_width > 3
          bookmark_text = bookmark_text[0...available_width - 3] + "..."
        elsif available_width <= 3
          bookmark_text = ""
        end

        # フッタ全体を構築
        if right_info.empty?
          footer_content = bookmark_text.ljust(@screen_width)[0...@screen_width]
        else
          padding = @screen_width - bookmark_text.length - right_info.length
          footer_content = "#{bookmark_text}#{' ' * padding}#{right_info}"
          footer_content = footer_content.ljust(@screen_width)[0...@screen_width]
        end
        screen.put_string(0, y, footer_content, fg: "\e[90m")

        # Tab ジャンプ時：対象ブックマークを 500ms ハイライト（セカンドパス）
        if @highlighted_bookmark_index && !bookmark_highlight_expired? && available_width > 3
          highlight_idx = @highlighted_bookmark_index
          if highlight_idx < bookmark_parts.length
            separator_len = 3  # " │ "
            x_pos = bookmark_parts[0...highlight_idx].sum { |p| p.length + separator_len }
            part_text = bookmark_parts[highlight_idx]
            if x_pos < available_width
              visible_len = [part_text.length, available_width - x_pos].min
              screen.put_string(x_pos, y, part_text[0...visible_len], fg: "\e[1;36m")
            end
          end
        end
      end
    end

    # ============================
    # モードタブ描画
    # ============================

    def draw_mode_tabs_to_buffer(screen, y)
      # タブモードマネージャの状態を同期
      sync_tab_mode_with_keybind_handler

      current_x = 0
      modes = @tab_mode_manager.available_modes
      labels = @tab_mode_manager.mode_labels
      keys = @tab_mode_manager.mode_keys
      current_mode = @tab_mode_manager.current_mode

      modes.each_with_index do |mode, index|
        key = keys[mode]
        label = key ? " #{key}:#{labels[mode]} " : " #{labels[mode]} "

        if mode == current_mode
          label.each_char do |char|
            screen.put(current_x, y, char, fg: "\e[30m\e[1m", bg: "\e[46m")
            current_x += 1
          end
        else
          label.each_char do |char|
            screen.put(current_x, y, char, fg: "\e[90m")
            current_x += 1
          end
        end

        # セパレータ
        if index < modes.length - 1
          if mode == current_mode
            screen.put(current_x, y, "\uE0B0", fg: "\e[36m")
          else
            screen.put(current_x, y, TAB_SEPARATOR, fg: "\e[90m")
          end
          current_x += 1
        end
      end

      # パスとバージョン情報を行末に追加
      current_path = @directory_listing.current_path
      version_str = " rufio v#{VERSION}"
      version_w = version_str.length

      remaining_w = @screen_width - current_x
      path_display_w = remaining_w - 2 - version_w

      if path_display_w >= 3
        arrow_fg = modes.last == current_mode ? "\e[36m" : "\e[90m"
        screen.put(current_x, y, TAB_SEPARATOR, fg: arrow_fg)
        current_x += 1

        path_end = @screen_width - 1 - version_w
        path_str = " #{current_path} "
        path_str.each_char do |char|
          break if current_x >= path_end
          char_w = TextUtils.display_width(char)
          break if current_x + char_w > path_end
          screen.put(current_x, y, char, fg: "\e[90m")
          current_x += char_w
        end

        while current_x < path_end
          screen.put(current_x, y, ' ')
          current_x += 1
        end

        screen.put(current_x, y, "\uE0B2", fg: "\e[36m")
        current_x += 1

        version_str.each_char do |char|
          break if current_x >= @screen_width
          screen.put(current_x, y, char, fg: "\e[30m\e[1m", bg: "\e[46m")
          current_x += 1
        end
      end

      # 残りをスペースで埋める
      while current_x < @screen_width
        screen.put(current_x, y, ' ')
        current_x += 1
      end
    end

    # ============================
    # ジョブモード描画
    # ============================

    def draw_job_list_to_buffer(screen, height, job_manager, job_mode_instance)
      return unless job_manager

      jobs = job_manager.jobs
      selected_index = job_mode_instance&.selected_index || 0

      (0...height).each do |i|
        line_num = i + CONTENT_START_LINE

        if i < jobs.length
          job = jobs[i]
          draw_job_line_to_buffer(screen, job, i == selected_index, line_num)
        else
          screen.put_string(0, line_num, ' ' * @screen_width)
        end
      end
    end

    def draw_job_line_to_buffer(screen, job, is_selected, y)
      icon = job.status_icon
      name = job.name
      path = "(#{job.path})"
      duration = job.formatted_duration
      duration_text = duration.empty? ? "" : "[#{duration}]"

      status_text = case job.status
                    when :running then "Running"
                    when :completed then "Done"
                    when :failed then "Failed"
                    when :waiting then "Waiting"
                    when :cancelled then "Cancelled"
                    else ""
                    end

      status_color = case job.status
                     when :running then "\e[33m"
                     when :completed then "\e[32m"
                     when :failed then "\e[31m"
                     else "\e[37m"
                     end

      line_content = "#{icon} #{name} #{path}".ljust(40)
      line_content += "#{duration_text.ljust(12)} #{status_text}"
      line_content = line_content[0...@screen_width].ljust(@screen_width)

      if is_selected
        line_content.each_char.with_index do |char, x|
          screen.put(x, y, char, fg: "\e[30m", bg: "\e[47m")
        end
      else
        line_content.each_char.with_index do |char, x|
          screen.put(x, y, char, fg: status_color)
        end
      end
    end

    def draw_job_footer_to_buffer(screen, y, job_manager)
      job_count = job_manager&.job_count || 0
      help_text = "[Space] View Log | [x] Cancel | [Tab] Switch Mode | Jobs: #{job_count}"
      footer_content = help_text.center(@screen_width)[0...@screen_width]

      footer_content.each_char.with_index do |char, x|
        screen.put(x, y, char, fg: "\e[30m", bg: "\e[47m")
      end
    end

    # ============================
    # ヘルパーメソッド
    # ============================

    private

    def get_display_entries
      entries = if @keybind_handler.filter_active?
                  all_entries = @directory_listing.list_entries
                  query = @keybind_handler.filter_query.downcase
                  query.empty? ? all_entries : all_entries.select { |entry| entry[:name].downcase.include?(query) }
                else
                  @directory_listing.list_entries
                end

      # ヘルプモードとLogsモードでは..を非表示にする
      if @keybind_handler.help_mode? || @keybind_handler.log_viewer_mode?
        entries.reject { |entry| entry[:name] == '..' }
      else
        entries
      end
    end

    # キーバインドハンドラの状態とタブモードを同期
    def sync_tab_mode_with_keybind_handler
      return unless @keybind_handler

      current_mode = if @keybind_handler.in_job_mode?
                       :jobs
                     elsif @keybind_handler.help_mode?
                       :help
                     elsif @keybind_handler.log_viewer_mode?
                       :logs
                     else
                       :files
                     end

      @tab_mode_manager.switch_to(current_mode) if @tab_mode_manager.current_mode != current_mode
    end
  end
end
