# frozen_string_literal: true

require_relative "rufio/version"
require_relative "rufio/config"
require_relative "rufio/config_loader"
require_relative "rufio/color_helper"
require_relative "rufio/directory_listing"
require_relative "rufio/filter_manager"
require_relative "rufio/selection_manager"
require_relative "rufio/file_operations"
require_relative "rufio/bookmark_storage"
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

# DSLコマンドシステム
require_relative "rufio/interpreter_resolver"
require_relative "rufio/dsl_command"
require_relative "rufio/script_executor"
require_relative "rufio/dsl_command_loader"
require_relative "rufio/builtin_commands"

require_relative "rufio/command_mode"
require_relative "rufio/command_mode_ui"
require_relative "rufio/command_history"
require_relative "rufio/command_completion"
require_relative "rufio/shell_command_completion"
require_relative "rufio/command_logger"
require_relative "rufio/background_command_executor"
require_relative "rufio/native_scanner"
require_relative "rufio/native_scanner_zig"
require_relative "rufio/async_scanner_promise"
require_relative "rufio/async_scanner_fiber"
require_relative "rufio/parallel_scanner"
require_relative "rufio/screen"
require_relative "rufio/renderer"
require_relative "rufio/tab_mode_manager"

# ジョブ管理システム
require_relative "rufio/task_status"
require_relative "rufio/notification_manager"
require_relative "rufio/job_manager"
require_relative "rufio/job_mode"
require_relative "rufio/script_runner"
require_relative "rufio/script_path_manager"
require_relative "rufio/script_config_loader"

module Rufio
  class Error < StandardError; end
end