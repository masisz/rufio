# frozen_string_literal: true

require_relative 'text_utils'
require_relative 'dialog_renderer'
require_relative 'config_loader'

module Rufio
  # メインループを止めずに表示するヘルプメニュー。
  class HelpMenu
    SECTIONS = %w[Controls Modes Scripts].freeze
    attr_reader :scroll_offset

    def initialize
      @active = false
      @section_index = 0
      @scroll_offset = 0
      @max_scroll = 0
    end

    def open
      @active = true
      @section_index = 0
      @scroll_offset = 0
    end

    def active?
      @active
    end

    def section
      SECTIONS[@section_index]
    end

    def handle_key(key)
      case key
      when "\e", 'q', '?' then @active = false
      when '1', '2', '3' then select_section(key.to_i - 1)
      when "\t", 'l' then select_section((@section_index + 1) % SECTIONS.length)
      when 'h', "\e[Z" then select_section((@section_index - 1) % SECTIONS.length)
      when 'j' then @scroll_offset = [@scroll_offset + 1, @max_scroll].min
      when 'k' then @scroll_offset = [@scroll_offset - 1, 0].max
      when "\x04" then @scroll_offset = [@scroll_offset + @page_size.to_i, @max_scroll].min
      when "\x15" then @scroll_offset = [@scroll_offset - @page_size.to_i, 0].max
      when 'g' then @scroll_offset = 0
      when 'G' then @scroll_offset = @max_scroll
      end
      true
    end

    def content
      case section
      when 'Controls'
        [
          'Navigation',
          "#{key(:move_down)}/#{key(:move_up)} or arrows: Move down/up",
          "#{key(:navigate_parent)}/#{key(:navigate_enter)}: Parent / enter directory",
          'Enter: Open file preview | ESC: Back to file list',
          'Preview: j/k scroll, Ctrl+D/U page down/up',
          "#{key(:top)}/#{key(:bottom)}: First / last entry",
          "#{key(:open_file)}: Open in external editor",
          "#{key(:refresh)}: Refresh directory",
          '', 'Selection and file operations',
          "#{key(:select)}: Select / unselect file",
          "#{key(:copy_selected)}/#{key(:move_selected)}/#{key(:delete_selected)}: Copy / move / delete selected files",
          "#{key(:rename)}/#{key(:delete)}: Rename / delete current file",
          "#{key(:create_file)}/#{key(:create_dir)}: Create file / directory",
          '', 'Search and bookmarks',
          "#{key(:filter)}: Filter | Enter: Apply | ESC: Clear",
          "#{key(:fzf_search)}: Filename search (fzf)",
          "#{key(:rga_search)}: Content search (rga)",
          "#{key(:global_search)}: Search file names or contents across all bookmarks",
          "#{key(:add_bookmark)}/#{key(:bookmark_menu)}: Add / manage bookmarks",
          'Tab / Shift+Tab: Next / previous bookmark',
          "1-9: Jump to bookmark | #{key(:start_dir)}: Start directory",
          "#{key(:zoxide)}: Directory history (zoxide)",
          "#{key(:quit)}: Quit (with confirmation)",
          "#{key(:quit_cd)}: Quit and cd to the current directory (rufio --shell-init)"
        ]
      when 'Modes'
        [
          'Files', 'Browse directories, select files and view previews.',
          '', "[#{key(:config_mode)}] Config",
          'Open ~/.config/rufio/ to edit settings and scripts.',
          'The config directory is created if it does not exist.',
          'Navigation, previews and file operations work as in Files.',
          "#{key(:navigate_parent)}: Parent directory; leaving config returns to Files.",
          '', "[#{key(:global_search)}] Global search",
          'Search file names or text inside every bookmarked directory.',
          'Tab: Switch File names / Content (literal, case insensitive)',
          'Content results show file, line number and matching text.',
          'Documents: .pdf (page), .xlsx (sheet/cell), .pptx (slide)',
          'Ruby extracts document text; no Python or Office is needed.',
          'Unchanged document text is cached in memory for faster searches.',
          'Images need OCR; legacy .xls/.ppt and slide notes are unsupported.',
          'Yellow Searching... + spinner: Search is running.',
          'Green Search complete: All bookmarked directories scanned.',
          'Exclude extensions in ~/.config/rufio/config.rb:',
          'GLOBAL_SEARCH_EXCLUDED_EXTENSIONS = %w[.zip .log]',
          'Applies to names and contents. Restart Rufio after editing.',
          'Extensions ignore case; leading dots are optional; [] excludes none.',
          'Type to filter | Up/Down or Ctrl+N/P: Select',
          'Enter: Go to the selected file in Files mode',
          'ESC: Return to the previous mode | Ctrl+U: Clear query',
          '', "[#{key(:log_viewer)}] Logs",
          'Browse command logs. Enter opens a preview.',
          'ESC: Leave preview; ESC again: Return to Files.',
          '', "[#{key(:job_mode)}] Jobs",
          'View background commands and their status.',
          'Space: View log | x: Cancel job | ESC: Back',
          '', "[#{key(:help)}] Help",
          'This floating menu keeps your current mode and directory.',
          '1/2/3 or Tab: Select section | ESC: Close',
          '', "[#{key(:command_mode)}] Command",
          'Type a command, then Enter to run it.',
          'Tab: Complete | Up/Down: History | ESC: Cancel',
          ':!git status: Run a shell command',
          ':@hello.rb: Run a script in the current directory'
        ]
      when 'Scripts'
        [
          '1. Personal scripts',
          'Place scripts in ~/.config/rufio/scripts/',
          'Example: ~/.config/rufio/scripts/hello.rb',
          'Press : and type hello, then Enter (:hello).',
          '', '2. Additional script folders',
          'List folders in ~/.config/rufio/script_paths.yml:',
          '- ~/.config/rufio/scripts', '- ~/my-scripts',
          'Folders are searched in order. First matching name wins.',
          '', '3. Project scripts',
          'Place hello.rb or hello.sh in the directory you browse.',
          'Run it with :@hello.rb or :@hello.sh.',
          'Project search paths: ./rufio.yml, script_paths list.',
          '', '4. Run and monitor',
          'Tab completes script names. Up/Down recalls commands.',
          "#{key(:job_mode)}: Background jobs | #{key(:log_viewer)}: Execution logs",
          'Supported: Ruby, shell, Python and other script types.'
        ]
      end
    end

    def draw(screen)
      width = [screen.width, 78].min
      height = [screen.height, 26].min
      return if width < 8 || height < 8

      @page_size = height - 7
      lines = content.flat_map { |line| line.empty? ? [''] : TextUtils.wrap_preview_lines([line], width - 4) }
      @max_scroll = [lines.length - @page_size, 0].max
      @scroll_offset = [@scroll_offset, @max_scroll].min
      tabs = SECTIONS.each_with_index.map do |name, index|
        index == @section_index ? "[#{index + 1}:#{name}]" : " #{index + 1}:#{name} "
      end.join(' ')
      visible = [TextUtils.truncate_to_width(tabs, width - 2), '']
      visible.concat(lines.slice(@scroll_offset, @page_size) || [])
      visible << '' while visible.length < height - 5
      visible << TextUtils.truncate_to_width('ESC: Close | Tab: Menu | j/k: Scroll', width - 2)
      screen.enable_overlay
      screen.clear_overlay
      title = "Help - #{section} (#{@scroll_offset + 1}/#{@max_scroll + 1})"
      DialogRenderer.new.draw_floating_window_to_overlay(
        screen, (screen.width - width) / 2, (screen.height - height) / 2,
        width, height, TextUtils.truncate_to_width(title, width - 2), visible,
        border_color: "\e[36m", title_color: "\e[1;36m"
      )
    end

    private

    def select_section(index)
      @section_index = index
      @scroll_offset = 0
    end

    def key(action)
      value = ConfigLoader.keybinds[action]
      value == ' ' ? 'Space' : value.to_s
    end
  end
end
