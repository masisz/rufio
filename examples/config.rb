# frozen_string_literal: true

# ~/.config/rufio/config.rb
# rufio DSL Configuration File
#
# This file defines the configuration for rufio.
# Script paths and bookmarks are managed in separate YAML files.

# ========================================
# Language Setting
# ========================================
# 'en' (English) or 'ja' (Japanese)
LANGUAGE = 'ja'

# ========================================
# Color Settings
# ========================================
# HSL format: [hue(0-360), saturation(0-100), lightness(0-100)]
COLORS = {
  directory: { hsl: [220, 80, 60] },    # Blue
  file: { hsl: [0, 0, 90] },            # White
  executable: { hsl: [120, 70, 50] },   # Green
  selected: { hsl: [50, 90, 70] },      # Yellow
  preview: { hsl: [180, 60, 65] }       # Cyan
}.freeze

# ========================================
# Keybind Settings
# ========================================
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
}.freeze

# ========================================
# Application Associations
# ========================================
# Specify which application to open for each file extension
APPLICATIONS = {
  %w[txt md rb py js html css json xml yaml yml] => 'code',
  %w[jpg jpeg png gif bmp svg webp] => 'open',
  %w[mp4 avi mkv mov wmv] => 'open',
  %w[pdf] => 'open',
  %w[doc docx xls xlsx ppt pptx] => 'open',
  :default => 'open'
}.freeze

# ========================================
# Command History Size
# ========================================
COMMAND_HISTORY_SIZE = 1000

# ========================================
# Script Paths and Bookmarks
# ========================================
# script_paths.yml - List of script directories
# bookmarks.yml    - List of bookmarks
#
# These files are automatically loaded by rufio.
# You can edit them manually or manage via rufio's UI.
