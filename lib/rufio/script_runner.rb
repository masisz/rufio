# frozen_string_literal: true

require 'open3'

module Rufio
  # スクリプトパスからスクリプトを検索・実行するクラス
  # ジョブマネージャーと連携してバックグラウンド実行を管理
  class ScriptRunner
    # サポートするスクリプト拡張子
    SUPPORTED_EXTENSIONS = %w[.sh .rb .py .pl .js .ts .ps1].freeze

    # @param script_paths [Array<String>] スクリプトを検索するディレクトリのリスト
    # @param job_manager [JobManager, nil] ジョブマネージャー（nilの場合は同期実行）
    def initialize(script_paths:, job_manager: nil)
      @script_paths = script_paths.map { |p| File.expand_path(p) }
      @job_manager = job_manager
      @scripts_cache = nil
    end

    # 利用可能なスクリプト一覧を取得
    # @return [Array<Hash>] スクリプト情報の配列 [{ name:, path:, dir: }, ...]
    def available_scripts
      @scripts_cache ||= scan_scripts
    end

    # スクリプト名で検索
    # @param name [String] スクリプト名（拡張子あり/なし）
    # @return [Hash, nil] スクリプト情報 { name:, path:, dir: } または nil
    def find_script(name)
      # 完全一致を優先
      script = available_scripts.find { |s| s[:name] == name }
      return script if script

      # 拡張子なしで検索
      SUPPORTED_EXTENSIONS.each do |ext|
        script = available_scripts.find { |s| s[:name] == "#{name}#{ext}" }
        return script if script
      end

      nil
    end

    # スクリプト名の補完候補を取得
    # @param prefix [String] 入力中の文字列
    # @return [Array<String>] 補完候補のスクリプト名
    def complete(prefix)
      available_scripts
        .map { |s| s[:name] }
        .select { |name| name.start_with?(prefix) }
        .uniq
        .sort
    end

    # スクリプトをジョブとして実行
    # @param name [String] スクリプト名
    # @param working_dir [String] 作業ディレクトリ
    # @param selected_file [String, nil] 選択中のファイル
    # @param selected_dir [String, nil] 選択中のディレクトリ
    # @return [TaskStatus, nil] 作成されたジョブ、またはスクリプトが見つからない場合nil
    def run(name, working_dir:, selected_file: nil, selected_dir: nil)
      script = find_script(name)
      return nil unless script

      env = build_environment(working_dir, selected_file, selected_dir)
      execute_script(script, working_dir, env)
    end

    # キャッシュをクリア
    def clear_cache
      @scripts_cache = nil
    end

    private

    # スクリプトディレクトリをスキャンしてスクリプトを収集
    # @return [Array<Hash>] スクリプト情報の配列
    def scan_scripts
      scripts = []
      seen_names = Set.new

      @script_paths.each do |dir|
        next unless Dir.exist?(dir)

        Dir.glob(File.join(dir, '**', '*')).each do |path|
          next unless File.file?(path)
          next unless executable_script?(path)

          name = File.basename(path)
          # 最初に見つかったものを優先（同名スクリプトは先のパスが優先）
          next if seen_names.include?(name)

          seen_names.add(name)
          scripts << {
            name: name,
            path: path,
            dir: dir
          }
        end
      end

      scripts.sort_by { |s| s[:name] }
    end

    # 実行可能なスクリプトかどうかを判定
    # @param path [String] ファイルパス
    # @return [Boolean]
    def executable_script?(path)
      ext = File.extname(path).downcase
      return true if SUPPORTED_EXTENSIONS.include?(ext)

      # 拡張子がなくても実行可能なら対象
      File.executable?(path)
    end

    # 環境変数を構築
    # @param working_dir [String] 作業ディレクトリ
    # @param selected_file [String, nil] 選択中のファイル
    # @param selected_dir [String, nil] 選択中のディレクトリ
    # @return [Hash] 環境変数のハッシュ
    def build_environment(working_dir, selected_file, selected_dir)
      env = {
        'RUFIO_CURRENT_DIR' => working_dir
      }
      env['RUFIO_SELECTED_FILE'] = selected_file if selected_file
      env['RUFIO_SELECTED_DIR'] = selected_dir if selected_dir
      env
    end

    # スクリプトを実行してジョブを作成
    # @param script [Hash] スクリプト情報
    # @param working_dir [String] 作業ディレクトリ
    # @param env [Hash] 環境変数
    # @return [TaskStatus] 作成されたジョブ
    def execute_script(script, working_dir, env = {})
      command = build_command(script)

      if @job_manager
        # ジョブマネージャーにジョブを追加
        job = @job_manager.add_job(
          name: script[:name],
          path: working_dir,
          command: command
        )
        job.start

        # バックグラウンドで実行
        Thread.new do
          execute_in_background(job, command, working_dir, env)
        end

        job
      else
        # 同期実行（ジョブマネージャーがない場合）
        stdout, stderr, status = Open3.capture3(env, command, chdir: working_dir)
        {
          success: status.success?,
          output: stdout,
          error: stderr,
          exit_code: status.exitstatus
        }
      end
    end

    # スクリプトの実行コマンドを構築
    # @param script [Hash] スクリプト情報
    # @return [String] 実行コマンド
    def build_command(script)
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
        # shスクリプトまたは実行可能ファイル
        path.shellescape
      end
    end

    # バックグラウンドでスクリプトを実行
    # @param job [TaskStatus] ジョブ
    # @param command [String] 実行コマンド
    # @param working_dir [String] 作業ディレクトリ
    # @param env [Hash] 環境変数
    def execute_in_background(job, command, working_dir, env = {})
      stdout, stderr, status = Open3.capture3(env, command, chdir: working_dir)

      # ログを追加
      job.append_log(stdout) unless stdout.empty?
      job.append_log(stderr) unless stderr.empty?

      if status.success?
        job.complete(exit_code: status.exitstatus)
      else
        job.fail(exit_code: status.exitstatus)
      end

      # 通知を送信
      @job_manager&.notify_completion(job)
    rescue StandardError => e
      job.append_log("Error: #{e.message}")
      job.fail(exit_code: -1)
      @job_manager&.notify_completion(job)
    end
  end
end
