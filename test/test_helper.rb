# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "rufio"

require "minitest"
require "fileutils"
require "tmpdir"

# minitestのプラグインを無効化してRailsとの競合を回避
ENV['MT_PLUGINS'] = ""
ENV['NO_PLUGINS'] = "true"

# 手動でminitestを実行
Minitest.run if __FILE__ == $0