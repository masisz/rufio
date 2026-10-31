# frozen_string_literal: true

require_relative 'dialog_support'
require_relative 'zip_extractor'
require_relative 'zip_writer'

module Rufio
  # 選択中のアイテムを z キーで圧縮・展開するコントローラ
  #
  # - 選択がすべて .zip ファイルなら、それぞれを現在のディレクトリの <名前>/ に展開する
  # - それ以外は選択アイテムを 1 つの ZIP にまとめて現在のディレクトリに作成する
  # 処理は JobManager のジョブとしてバックグラウンドで実行し、Jobs モードからキャンセルできる。
  class ArchiveController
    include DialogSupport

    DEFAULT_ARCHIVE_NAME = 'Archive.zip'
    DIALOG_WIDTH = 50
    DIALOG_BORDER_HEIGHT = 4
    PROGRESS_STEP = 5 # 進捗表示を更新する間隔（%）

    Plan = Struct.new(:action, :source_dir, :dest_dir, :items, :archives, :default_name, keyword_init: true)

    def initialize(directory_listing, dialog_renderer, selection_manager, job_manager, notification_manager)
      @directory_listing = directory_listing
      @dialog_renderer = dialog_renderer
      @selection_manager = selection_manager
      @job_manager = job_manager
      @notification_manager = notification_manager
      @terminal_ui = nil
      @mutex = Mutex.new
      @finished_dirs = []
      @progress_changed = false
    end

    def set_terminal_ui(terminal_ui)
      @terminal_ui = terminal_ui
    end

    def set_directory_listing(directory_listing)
      @directory_listing = directory_listing
    end

    # 選択アイテムから実行内容を決める（UI に依存しない）
    def self.plan(source_dir, items, dest_dir)
      items = items.reject { |item| item == '..' }
      return nil if items.empty?

      paths = items.map { |item| File.join(source_dir, item) }
      if paths.all? { |path| File.file?(path) && File.extname(path).casecmp?('.zip') }
        archives = paths.map { |path| [path, unique_path(dest_dir, File.basename(path, '.*'), '')] }
        Plan.new(action: :extract, source_dir: source_dir, dest_dir: dest_dir, items: items, archives: archives)
      else
        default_name = items.length == 1 ? "#{File.basename(items.first)}.zip" : DEFAULT_ARCHIVE_NAME
        Plan.new(action: :compress, source_dir: source_dir, dest_dir: dest_dir, items: items, default_name: default_name)
      end
    end

    # dir/base<ext> が既にあれば "base 2<ext>", "base 3<ext>" ... を返す
    def self.unique_path(dir, base, ext)
      candidate = File.join(dir, "#{base}#{ext}")
      number = 2
      while File.exist?(candidate) || File.symlink?(candidate)
        candidate = File.join(dir, "#{base} #{number}#{ext}")
        number += 1
      end
      candidate
    end

    # 入力されたアーカイブ名を検証して .zip を補う（不正なら nil）
    def self.archive_name(input, default_name)
      name = input.to_s.strip
      name = default_name if name.empty?
      return nil if name.match?(%r{[/\\\0]}) || ['.', '..'].include?(name)

      File.extname(name).casecmp?('.zip') ? name : "#{name}.zip"
    end

    # z キー（選択あり）の入口
    def archive_selected
      return false if @selection_manager.empty?

      current_path = @directory_listing&.current_path || Dir.pwd
      source_dir = @selection_manager.source_directory || current_path
      plan = self.class.plan(source_dir, @selection_manager.selected_items, current_path)
      return false unless plan

      started = plan.action == :extract ? confirm_and_extract(plan) : prompt_and_compress(plan)
      @selection_manager.clear if started
      @terminal_ui&.refresh_display
      started
    end

    def start_extract(zip_path, dest_dir)
      run_job("Extract #{File.basename(zip_path)}", [File.dirname(dest_dir), dest_dir]) do |job, progress|
        created = !File.exist?(dest_dir)
        begin
          result = ZipExtractor.new(zip_path, dest_dir, progress: progress, cancelled: -> { job.cancelled? }).extract
        rescue StandardError
          # 新しく作った展開先だけを片付ける（既存ディレクトリには触れない）
          FileUtils.rm_rf(dest_dir) if created
          raise
        end
        job.append_log("Extracted #{result.extracted.length} item(s) to #{dest_dir}")
        result.skipped.each { |skip| job.append_log("Skipped #{skip[:name]} (#{skip[:reason]})") }
      end
    end

    def start_compress(zip_path, source_dir, items)
      run_job("Compress #{File.basename(zip_path)}", [File.dirname(zip_path)]) do |job, progress|
        result = ZipWriter.new(zip_path, source_dir, items, progress: progress, cancelled: -> { job.cancelled? }).write
        job.append_log("Created #{zip_path} with #{result.added.length} item(s)")
        result.skipped.each { |skip| job.append_log("Skipped #{skip[:name]} (#{skip[:reason]})") }
      end
    end

    # メインループから呼ぶ。表示を更新すべき変化があれば true
    def poll
      finished, changed = @mutex.synchronize do
        dirs = @finished_dirs
        @finished_dirs = []
        progress = @progress_changed
        @progress_changed = false
        [dirs, progress || !dirs.empty?]
      end

      current = @directory_listing&.current_path
      @directory_listing.refresh if current && finished.any? { |dir| File.expand_path(dir) == File.expand_path(current) }
      changed
    end

    private

    def confirm_and_extract(plan)
      lines = ['', "Extract #{plan.archives.length} archive(s)?", '']
      plan.archives.first(5).each do |zip, dest|
        lines << "  #{TextUtils.shorten_path_from_end(File.basename(zip), 20)} -> #{TextUtils.shorten_path_from_end(File.basename(dest), 20)}/"
      end
      lines << "  ... #{plan.archives.length - 5} more" if plan.archives.length > 5
      lines += ['', "To: #{TextUtils.shorten_path_from_end(plan.dest_dir, 40)}", '', '  [Y]es - Extract', '  [N]o  - Cancel', '']

      return false unless confirm_dialog('Extract Archives', lines, dialog_options(lines))

      plan.archives.each { |zip, dest| start_extract(zip, dest) }
      true
    end

    def prompt_and_compress(plan)
      input = @dialog_renderer.show_input_dialog(
        "Compress #{plan.items.length} item(s)",
        "Archive name (Enter: #{plan.default_name}):",
        { width: DIALOG_WIDTH, border_color: "\e[36m", title_color: "\e[1;36m", content_color: "\e[37m" }
      )
      return false if input.nil?

      name = self.class.archive_name(input, plan.default_name)
      zip_path = name && File.join(plan.dest_dir, name)
      if zip_path.nil? || File.exist?(zip_path)
        message = zip_path ? "Already exists: #{name}" : "Invalid archive name: #{input}"
        @notification_manager&.add(message, :error, duration: 3, exit_code: nil)
        return false
      end

      start_compress(zip_path, plan.source_dir, plan.items)
      true
    end

    def dialog_options(lines)
      {
        width: DIALOG_WIDTH,
        height: DIALOG_BORDER_HEIGHT + lines.length,
        border_color: "\e[36m",
        title_color: "\e[1;36m",
        content_color: "\e[37m"
      }
    end

    # refresh_dirs: 完了時に表示中なら再読み込みするディレクトリ
    def run_job(name, refresh_dirs)
      job = @job_manager.add_job(name: name, path: refresh_dirs.first, command: nil)
      job.start
      last_percent = -PROGRESS_STEP
      progress = lambda do |done, total|
        percent = total.zero? ? 100 : (done * 100 / total)
        next if percent < last_percent + PROGRESS_STEP

        last_percent = percent
        job.name = "#{name} #{percent}%"
        @mutex.synchronize { @progress_changed = true }
      end

      Thread.new do
        begin
          yield job, progress
          job.name = name
          job.complete(exit_code: 0) unless job.cancelled?
        rescue ZipExtractor::CancelledError, ZipWriter::CancelledError
          job.name = name
          job.append_log('Cancelled')
        rescue StandardError => e
          job.name = name
          job.append_log("Error: #{e.message}")
          job.fail(exit_code: 1) unless job.cancelled?
        ensure
          @job_manager.notify_completion(job) unless job.cancelled?
          @mutex.synchronize { @finished_dirs.concat(refresh_dirs) }
        end
      end
      job
    end
  end
end
