# frozen_string_literal: true

# rufio configuration example
# Copy this file to ~/.config/rufio/config.rb to customize your settings

# Cross-platform file opener method
def get_system_open_command
  case RbConfig::CONFIG['host_os']
  when /mswin|mingw|cygwin/
    'start'  # Windows
  when /darwin/
    'open'   # macOS
  when /linux|bsd/
    'xdg-open'  # Linux/BSD
  else
    'open'   # Fallback to open
  end
end

# Get the appropriate open command for current platform
SYSTEM_OPEN = get_system_open_command

# Language setting
# Available languages: 'en' (English), 'ja' (Japanese)
# If not specified, language will be auto-detected from environment variables
LANGUAGE = 'en'  # or 'ja'

# Application associations
# Define which applications to use for opening different file types
APPLICATIONS = {
  # Text files - open with 'code' (VS Code)
  %w[txt md rb py js ts html css json xml yaml yml] => 'code',
  
  # Image files - open with default system app
  %w[jpg jpeg png gif bmp svg webp] => SYSTEM_OPEN,
  
  # Video files - open with default system app
  %w[mp4 avi mkv mov wmv] => SYSTEM_OPEN,
  
  # Documents - open with default system app
  %w[pdf doc docx xls xlsx ppt pptx] => SYSTEM_OPEN,
  
  # Default application for unspecified file types
  :default => SYSTEM_OPEN
}

# Color scheme
# Define colors for different types of files and UI elements
# You can use various color formats:
#   - Symbols: :blue, :red, :green, :yellow, :cyan, :magenta, :white, :black
#   - HSL: {hsl: [hue(0-360), saturation(0-100), lightness(0-100)]}
#   - RGB: {rgb: [red(0-255), green(0-255), blue(0-255)]}
#   - HEX: {hex: "#ff0000"}
#   - ANSI codes: "34" or 34
COLORS = {
  # HSL color examples (Hue: 0-360, Saturation: 0-100%, Lightness: 0-100%)
  directory: { hsl: [220, 80, 60] },    # Blue directory entries
  file: { hsl: [0, 0, 90] },            # Light gray regular files
  executable: { hsl: [120, 70, 50] },   # Green executable files
  selected: { hsl: [50, 90, 70] },      # Yellow currently selected item
  preview: { hsl: [180, 60, 65] },      # Cyan preview panel
  
  # You can also mix different formats:
  # directory: :blue,                   # Traditional symbol
  # file: {rgb: [200, 200, 200]},       # RGB format
  # executable: {hex: "#00ff00"},       # HEX format
  # selected: "93",                     # ANSI code (bright yellow)
}

# Key bindings
# Customize keyboard shortcuts (not yet fully implemented)
KEYBINDS = {
  quit: %w[q ESC],
  up: %w[k UP],
  down: %w[j DOWN],
  left: %w[h LEFT],
  right: %w[l RIGHT ENTER],
  top: %w[g],
  bottom: %w[G],
  refresh: %w[r],
  search: %w[/],
  open_file: %w[o SPACE]
}

# You can also set language via environment variable:
# export BENIYA_LANG=ja    # Set to 'ja' for Japanese, 'en' for English
# Note: Only BENIYA_LANG is used for language detection
# System LANG variable is ignored to ensure English is the default