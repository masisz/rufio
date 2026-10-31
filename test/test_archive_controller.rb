# frozen_string_literal: true

require_relative 'test_helper'
require 'minitest/autorun'
require 'timeout'
require_relative 'support/zip_fixture'

class TestArchiveController < Minitest::Test
  Controller = Rufio::ArchiveController

  def setup
    @dir = Dir.mktmpdir('rufio-archive')
    File.write(File.join(@dir, 'a.txt'), 'alpha')
    FileUtils.mkdir_p(File.join(@dir, 'docs'))
    File.write(File.join(@dir, 'docs', 'b.txt'), 'beta')
    File.binwrite(File.join(@dir, 'one.zip'), ZipFixture.new.add('x.txt', 'x').to_s)
    File.binwrite(File.join(@dir, 'two.ZIP'), ZipFixture.new.add('y.txt', 'y').to_s)

    @listing = Rufio::DirectoryListing.new(@dir)
    @selection = Rufio::SelectionManager.new
    @notifications = Rufio::NotificationManager.new
    @jobs = Rufio::JobManager.new(notification_manager: @notifications)
    @controller = Controller.new(@listing, Rufio::DialogRenderer.new, @selection, @jobs, @notifications)
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def wait_for(job)
    Timeout.timeout(5) { Thread.pass while job.running? }
  end

  def test_plan_extracts_when_every_selected_item_is_a_zip
    plan = Controller.plan(@dir, %w[one.zip two.ZIP], @dir)

    assert_equal :extract, plan.action
    assert_equal [[File.join(@dir, 'one.zip'), File.join(@dir, 'one')],
                  [File.join(@dir, 'two.ZIP'), File.join(@dir, 'two')]], plan.archives
  end

  def test_plan_compresses_mixed_or_non_zip_selection
    assert_equal :compress, Controller.plan(@dir, %w[one.zip a.txt], @dir).action
    assert_equal 'docs.zip', Controller.plan(@dir, %w[docs], @dir).default_name
    assert_equal 'Archive.zip', Controller.plan(@dir, %w[a.txt docs], @dir).default_name
    assert_nil Controller.plan(@dir, [], @dir)
    assert_nil Controller.plan(@dir, ['..'], @dir)
    assert_equal %w[a.txt], Controller.plan(@dir, %w[.. a.txt], @dir).items
  end

  def test_unique_path_and_archive_name
    FileUtils.mkdir_p(File.join(@dir, 'one'))
    assert_equal File.join(@dir, 'one 2'), Controller.unique_path(@dir, 'one', '')

    assert_equal 'Archive.zip', Controller.archive_name('', 'Archive.zip')
    assert_equal 'backup.zip', Controller.archive_name('backup', 'Archive.zip')
    assert_equal 'b.ZIP', Controller.archive_name('b.ZIP', 'Archive.zip')
    assert_nil Controller.archive_name('../evil', 'Archive.zip')
    assert_nil Controller.archive_name('a\\b', 'Archive.zip')
  end

  def test_extract_job_completes_notifies_and_refreshes_listing
    job = @controller.start_extract(File.join(@dir, 'one.zip'), File.join(@dir, 'one'))
    wait_for(job)

    assert job.completed?, job.logs.inspect
    assert_equal 'Extract one.zip', job.name
    assert_equal 'x', File.read(File.join(@dir, 'one', 'x.txt'))
    assert @controller.poll
    assert_includes @listing.list_entries.map { |e| e[:name] }, 'one'
    refute @controller.poll
  end

  def test_failed_extract_removes_new_destination
    File.binwrite(File.join(@dir, 'evil.zip'), ZipFixture.new.add('ok.txt', 'ok').add('../evil.txt', 'e').to_s)
    job = @controller.start_extract(File.join(@dir, 'evil.zip'), File.join(@dir, 'evil'))
    wait_for(job)

    assert job.failed?
    assert(job.logs.any? { |line| line.include?('Parent directory reference') })
    refute File.exist?(File.join(@dir, 'evil'))
  end

  def test_compress_job_creates_archive
    zip = File.join(@dir, 'Archive.zip')
    job = @controller.start_compress(zip, @dir, %w[a.txt docs])
    wait_for(job)

    assert job.completed?, job.logs.inspect
    assert_equal %w[a.txt docs/ docs/b.txt], Rufio::ZipArchive.list(zip).entries.map(&:name)
  end

  def test_cancelled_job_leaves_no_archive
    @jobs.stub(:add_job, lambda { |**kw|
      Rufio::TaskStatus.new(id: 1, **kw).tap { |job| job.define_singleton_method(:start) { cancel } }
    }) do
      job = @controller.start_compress(File.join(@dir, 'c.zip'), @dir, %w[a.txt])
      Timeout.timeout(5) { sleep 0.01 until @controller.poll }
      assert job.cancelled?
    end
    refute File.exist?(File.join(@dir, 'c.zip'))
  end

  def test_z_key_uses_zoxide_without_selection_and_archives_with_selection
    handler = Rufio::KeybindHandler.new
    handler.set_directory_listing(@listing)
    assert handler.respond_to?(:poll_archive_jobs), 'TerminalUI calls poll_archive_jobs from the main loop'
    archive_calls = 0
    zoxide_calls = 0
    controller = handler.instance_variable_get(:@archive_controller)

    controller.stub(:archive_selected, -> { archive_calls += 1 }) do
      handler.stub(:show_zoxide_menu, -> { zoxide_calls += 1 }) do
        handler.handle_key('z')
        assert_equal [0, 1], [archive_calls, zoxide_calls]

        handler.instance_variable_get(:@selection_manager).toggle_selection({ name: 'a.txt' }, @dir)
        handler.handle_key('z')
        assert_equal [1, 1], [archive_calls, zoxide_calls]
      end
    end
  end
end
