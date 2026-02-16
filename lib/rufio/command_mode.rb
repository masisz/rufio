# frozen_string_literal: true

require 'open3'

module Rufio
  # コマンドモード - DSLコマンドを実行するための統一インターフェース
  # すべてのコマンドはDslCommandとして扱われる
  class CommandMode
    attr_accessor :background_executor
    attr_reader :script_runner, :script_path_manager

    def initialize(background_executor = nil)
      @commands = {}
      @background_executor = background_executor
      @script_runner = nil
      @script_path_manager = nil
      @job_manager = nil
      @local_script_scanner = LocalScriptScanner.new
      @rakefile_parser = RakefileParser.new
      load_builtin_commands
      load_dsl_commands
    end

    # ScriptRunnerを設定する
    # @param script_paths [Array<String>] スクリプトパス
    # @param job_manager [JobManager] ジョブマネージャー
    def setup_script_runner(script_paths:, job_manager:)
      @job_manager = job_manager
      @script_runner = ScriptRunner.new(
        script_paths: script_paths,
        job_manager: job_manager,
        command_logger: @background_executor&.command_logger
      )
    end

    # ScriptPathManagerを設定する（設定ファイルベース）
    # @param config_file [String] 設定ファイルのパス
    # @param job_manager [JobManager] ジョブマネージャー
    def setup_script_path_manager(config_file:, job_manager:)
      @job_manager = job_manager
      @script_path_manager = ScriptPathManager.new(config_file)
      # ScriptRunnerも設定（ScriptPathManagerのパスを使用）
      @script_runner = ScriptRunner.new(
        script_paths: @script_path_manager.paths,
        job_manager: job_manager,
        command_logger: @background_executor&.command_logger
      )
    end

    # 閲覧中ディレクトリを更新
    # @param directory [String] 現在の閲覧ディレクトリ
    def update_browsing_directory(directory)
      @local_script_scanner.update_directory(directory)
      @rakefile_parser.update_directory(directory)
    end

    # コマンドを実行する
    # @param command_string [String] コマンド文字列
    # @param working_dir [String, nil] 作業ディレクトリ（スクリプト実行時に使用）
    def execute(command_string, working_dir: nil)
      # 空のコマンドは無視
      return nil if command_string.nil? || command_string.strip.empty?

      # スクリプト実行 (@ で始まる場合)
      if command_string.strip.start_with?('@')
        return execute_script(command_string.strip[1..-1], working_dir)
      end

      # rakeタスク実行 (rake: で始まる場合)
      if command_string.strip.start_with?('rake:')
        task_name = command_string.strip[5..-1]
        return execute_rake_task(task_name, working_dir)
      end

      # シェルコマンドの実行 (! で始まる場合)
      if command_string.strip.start_with?('!')
        shell_command = command_string.strip[1..-1]

        # バックグラウンドエグゼキュータが利用可能な場合は非同期実行
        if @background_executor
          if @background_executor.execute_async(shell_command)
            return "🔄 Running in background: #{shell_command.split.first}"
          else
            return "⚠️  Command already running"
          end
        else
          # バックグラウンドエグゼキュータがない場合は同期実行
          return execute_shell_command(shell_command)
        end
      end

      # コマンド名を取得 (前後の空白を削除)
      command_name = command_string.strip.to_sym

      # 統一されたコマンドストアから検索
      command = @commands[command_name]
      if command
        # 内部コマンドを実行
        return execute_unified_command(command_name, command)
      end

      # 内部コマンドが見つからない場合、スクリプトパスから検索
      if @script_path_manager || @script_runner
        script_result = try_execute_script_from_paths(command_string.strip, working_dir)
        return script_result if script_result
      end

      "⚠️  コマンドが見つかりません: #{command_name}"
    end

    # 利用可能なコマンドのリストを取得
    def available_commands
      @commands.keys
    end

    # コマンドの情報を取得
    def command_info(command_name)
      command = @commands[command_name]
      return nil unless command

      {
        name: command_name,
        plugin: command[:source] || "dsl",
        description: command[:command].description
      }
    end

    # DSLコマンドをロードする
    # @param paths [Array<String>, nil] 設定ファイルのパス配列（nilの場合はデフォルトパス）
    def load_dsl_commands(paths = nil)
      loader = DslCommandLoader.new

      commands = if paths
                   loader.load_from_paths(paths)
                 else
                   loader.load
                 end

      # ユーザーDSLコマンドは既存のコマンドを上書きする（優先度が高い）
      commands.each do |cmd|
        @commands[cmd.name.to_sym] = {
          command: cmd,
          source: "dsl"
        }
      end
    end

    # スクリプト名を補完する
    # @param prefix [String] 入力中の文字列（@を含む）
    # @return [Array<String>] 補完候補（@付き）
    def complete_script(prefix)
      # @を除去して検索
      search_prefix = prefix.sub(/^@/, '')

      candidates = []

      # ScriptRunnerからの候補
      if @script_runner
        candidates += @script_runner.complete(search_prefix)
      end

      # ローカルスクリプトからの候補
      candidates += @local_script_scanner.complete(search_prefix)

      # 重複排除してソート、@付きで返す
      candidates.uniq.sort.map { |name| "@#{name}" }
    end

    # rakeタスク名を補完する
    # @param prefix [String] 入力中の文字列（rake:を含まない）
    # @return [Array<String>] 補完候補（rake:付き）
    def complete_rake_task(prefix)
      @rakefile_parser.complete(prefix).map { |name| "rake:#{name}" }
    end

    private

    # 組み込みコマンドをロードする
    def load_builtin_commands
      builtin = BuiltinCommands.load
      builtin.each do |name, cmd|
        @commands[name] = {
          command: cmd,
          source: "builtin"
        }
      end
    end

    # 統一されたコマンド実行
    # @param command_name [Symbol] コマンド名
    # @param command [Hash] コマンド情報 { command: DslCommand, source: String }
    # @return [Hash] 実行結果
    def execute_unified_command(command_name, command)
      dsl_cmd = command[:command]

      # バックグラウンドエグゼキュータが利用可能な場合は非同期実行
      if @background_executor
        command_display_name = command_name.to_s
        if @background_executor.execute_ruby_async(command_display_name) do
             ScriptExecutor.execute_command(dsl_cmd)
           end
          return "🔄 Running in background: #{command_display_name}"
        else
          return "⚠️  Command already running"
        end
      end

      # 同期実行
      ScriptExecutor.execute_command(dsl_cmd)
    end

    # シェルコマンドを実行する
    def execute_shell_command(shell_command)
      # コマンドが空の場合
      return { success: false, error: "コマンドが指定されていません" } if shell_command.strip.empty?

      begin
        # Open3を使って標準出力と標準エラーを分離して取得
        stdout, stderr, status = Open3.capture3(shell_command)

        result = {
          success: status.success?,
          output: stdout.strip,
          stderr: stderr.strip
        }

        # コマンドが失敗した場合、エラーメッセージを追加
        unless status.success?
          result[:error] = "コマンドが失敗しました (終了コード: #{status.exitstatus})"
        end

        result
      rescue Errno::ENOENT => e
        { success: false, error: "コマンドが見つかりません: #{e.message}" }
      rescue StandardError => e
        { success: false, error: "コマンド実行エラー: #{e.message}" }
      end
    end

    # スクリプトを実行する（@プレフィックス用）
    # ScriptRunner → LocalScriptScanner の順にフォールバック
    # @param script_input [String] スクリプト名（引数を含む場合あり）
    # @param working_dir [String, nil] 作業ディレクトリ
    # @return [String] 実行結果メッセージ
    def execute_script(script_input, working_dir)
      working_dir ||= Dir.pwd

      # スクリプト名と引数を分離（例: "retag.sh v0.70.0" → name="retag.sh", args="v0.70.0"）
      parts = script_input.split(' ', 2)
      script_name = parts[0]
      script_args = parts[1]

      # ScriptRunnerで検索
      if @script_runner
        job = @script_runner.run(script_name, working_dir: working_dir, args: script_args)
        return "🚀 ジョブを開始: #{script_name}" if job
      end

      # LocalScriptScannerにフォールバック
      local_script = @local_script_scanner.find_script(script_name)
      if local_script
        return execute_local_script(local_script, working_dir, script_args)
      end

      # どちらにも見つからない
      if @script_runner
        "⚠️  スクリプトが見つかりません: #{script_name}"
      else
        "⚠️  スクリプトランナーが設定されていません"
      end
    end

    # ローカルスクリプトを実行する
    # @param script [Hash] スクリプト情報 { name:, path:, dir: }
    # @param working_dir [String] 作業ディレクトリ
    # @param args [String, nil] スクリプトに渡す引数
    # @return [String, Hash] 実行結果メッセージ
    def execute_local_script(script, working_dir, args = nil)
      command = build_script_command(script)
      command = "#{command} #{args}" if args && !args.empty?

      if @job_manager
        job = @job_manager.add_job(
          name: script[:name],
          path: working_dir,
          command: command
        )
        job.start

        Thread.new do
          execute_script_in_background(job, script, working_dir, command)
        end

        "🚀 ジョブを開始: #{script[:name]}"
      else
        # 同期実行
        stdout, stderr, status = Open3.capture3(command, chdir: working_dir)
        result = {
          success: status.success?,
          output: stdout.strip,
          stderr: stderr.strip
        }

        # Logsに記録
        log_execution("@#{script[:name]}", result)

        result
      end
    end

    # 実行結果をCommandLoggerに記録
    # @param command_name [String] コマンド名
    # @param result [Hash] 実行結果 { success:, output:, stderr:, error: }
    def log_execution(command_name, result)
      logger = @background_executor&.command_logger
      return unless logger

      output = [result[:output], result[:stderr]].compact.reject(&:empty?).join("\n")
      logger.log(
        command_name,
        output,
        success: result[:success],
        error: result[:error]
      )
    end

    # スクリプトの実行コマンドを構築
    # @param script [Hash] スクリプト情報
    # @return [String] 実行コマンド
    def build_script_command(script)
      path = script[:path]
      ext = File.extname(path).downcase

      case ext
      when '.rb'
        "ruby #{path.shellescape}"
      when '.py'
        "python3 #{path.shellescape}"
      when '.js'
        "node #{path.shellescape}"
      when '.ts'
        "ts-node #{path.shellescape}"
      when '.pl'
        "perl #{path.shellescape}"
      when '.ps1'
        "pwsh #{path.shellescape}"
      else
        path.shellescape
      end
    end

    # ローカルスクリプトをバックグラウンドで実行
    def execute_script_in_background(job, script, working_dir, command)
      stdout, stderr, status = Open3.capture3(command, chdir: working_dir)

      job.append_log(stdout) unless stdout.empty?
      job.append_log(stderr) unless stderr.empty?

      if status.success?
        job.complete(exit_code: status.exitstatus)
      else
        job.fail(exit_code: status.exitstatus)
      end

      # Logsに記録
      log_execution("@#{script[:name]}", {
        success: status.success?,
        output: stdout.strip,
        stderr: stderr.strip
      })

      @job_manager&.notify_completion(job)
    rescue StandardError => e
      job.append_log("Error: #{e.message}")
      job.fail(exit_code: -1)
      log_execution("@#{script[:name]}", { success: false, output: '', stderr: e.message })
      @job_manager&.notify_completion(job)
    end

    # rakeタスクを実行する
    # @param task_name [String] タスク名
    # @param working_dir [String, nil] 作業ディレクトリ
    # @return [String, Hash] 実行結果
    def execute_rake_task(task_name, working_dir)
      unless @rakefile_parser.rakefile_exists?
        return "⚠️  Rakefileが見つかりません"
      end

      unless @rakefile_parser.tasks.include?(task_name)
        return "⚠️  rakeタスクが見つかりません: #{task_name}"
      end

      working_dir ||= Dir.pwd
      shell_command = "rake #{task_name.shellescape}"

      begin
        stdout, stderr, status = Open3.capture3(shell_command, chdir: working_dir)

        result = {
          success: status.success?,
          output: stdout.strip,
          stderr: stderr.strip
        }

        unless status.success?
          result[:error] = "コマンドが失敗しました (終了コード: #{status.exitstatus})"
        end

        # Logsに記録
        log_execution("rake:#{task_name}", result)

        result
      rescue Errno::ENOENT => e
        result = { success: false, error: "rakeが見つかりません: #{e.message}" }
        log_execution("rake:#{task_name}", result)
        result
      rescue StandardError => e
        result = { success: false, error: "rake実行エラー: #{e.message}" }
        log_execution("rake:#{task_name}", result)
        result
      end
    end

    # スクリプトパスからスクリプトを検索して実行を試みる
    # @param command_name [String] コマンド名
    # @param working_dir [String, nil] 作業ディレクトリ
    # @return [String, nil] 実行結果メッセージ、見つからない場合nil
    def try_execute_script_from_paths(command_name, working_dir)
      return nil unless @script_runner

      script = @script_runner.find_script(command_name)
      return nil unless script

      working_dir ||= Dir.pwd

      job = @script_runner.run(command_name, working_dir: working_dir)

      if job
        "🚀 ジョブを開始: #{script[:name]}"
      else
        nil
      end
    end
  end
end
