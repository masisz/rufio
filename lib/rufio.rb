# frozen_string_literal: true

require_relative "rufio/version"
require_relative "rufio/config"
require_relative "rufio/config_loader"
require_relative "rufio/color_helper"
require_relative "rufio/directory_listing"
require_relative "rufio/filter_manager"
require_relative "rufio/selection_manager"
require_relative "rufio/file_operations"
require_relative "rufio/bookmark_manager"
require_relative "rufio/bookmark"
require_relative "rufio/zoxide_integration"
require_relative "rufio/dialog_renderer"
require_relative "rufio/text_utils"
require_relative "rufio/logger"
require_relative "rufio/keybind_handler"
require_relative "rufio/file_preview"
require_relative "rufio/terminal_ui"
require_relative "rufio/application"
require_relative "rufio/file_opener"
require_relative "rufio/health_checker"

# プラグインシステム
require_relative "rufio/plugin_config"
require_relative "rufio/plugin"
require_relative "rufio/plugin_manager"
require_relative "rufio/command_mode"
require_relative "rufio/command_mode_ui"

# プロジェクトモード
require_relative "rufio/project_mode"
require_relative "rufio/project_command"
require_relative "rufio/project_log"

module Rufio
  class Error < StandardError; end
end