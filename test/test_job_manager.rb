# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/rufio/job_manager'
require_relative '../lib/rufio/notification_manager'

class TestJobManager < Minitest::Test
  def setup
    @notification_manager = Rufio::NotificationManager.new
    @manager = Rufio::JobManager.new(notification_manager: @notification_manager)
  end

  def test_initial_jobs_is_empty
    assert_equal 0, @manager.job_count
    assert_empty @manager.jobs
  end

  def test_add_job
    job = @manager.add_job(name: 'build.rb', path: './src', command: 'ruby build.rb')
    assert_equal 1, @manager.job_count
    assert_equal 'build.rb', job.name
    assert_equal './src', job.path
    assert_equal :waiting, job.status
  end

  def test_job_ids_are_unique
    job1 = @manager.add_job(name: 'task1.rb', path: '.', command: 'ruby task1.rb')
    job2 = @manager.add_job(name: 'task2.rb', path: '.', command: 'ruby task2.rb')
    refute_equal job1.id, job2.id
  end

  def test_find_job_by_id
    job = @manager.add_job(name: 'test.rb', path: '.', command: 'ruby test.rb')
    found = @manager.find_job(job.id)
    assert_equal job.id, found.id
    assert_equal job.name, found.name
  end

  def test_find_job_returns_nil_for_unknown_id
    found = @manager.find_job(999)
    assert_nil found
  end

  def test_running_count
    @manager.add_job(name: 'task1.rb', path: '.', command: 'echo 1')
    @manager.add_job(name: 'task2.rb', path: '.', command: 'echo 2')
    assert_equal 0, @manager.running_count

    # ジョブを開始状態に変更（テスト用）
    @manager.jobs.first.start
    assert_equal 1, @manager.running_count
  end

  def test_completed_count
    @manager.add_job(name: 'task1.rb', path: '.', command: 'echo 1')
    @manager.add_job(name: 'task2.rb', path: '.', command: 'echo 2')

    @manager.jobs.first.start
    @manager.jobs.first.complete(exit_code: 0)

    assert_equal 1, @manager.completed_count
  end

  def test_failed_count
    @manager.add_job(name: 'task1.rb', path: '.', command: 'echo 1')
    @manager.jobs.first.start
    @manager.jobs.first.fail(exit_code: 1)

    assert_equal 1, @manager.failed_count
  end

  def test_status_summary
    @manager.add_job(name: 'task1.rb', path: '.', command: 'echo 1')
    @manager.add_job(name: 'task2.rb', path: '.', command: 'echo 2')
    @manager.add_job(name: 'task3.rb', path: '.', command: 'echo 3')

    @manager.jobs[0].start
    @manager.jobs[0].complete(exit_code: 0)
    @manager.jobs[1].start

    summary = @manager.status_summary
    assert_equal 3, summary[:total]
    assert_equal 1, summary[:running]
    assert_equal 1, summary[:done]
    assert_equal 0, summary[:failed]
  end

  def test_cancel_job
    job = @manager.add_job(name: 'task.rb', path: '.', command: 'sleep 10')
    job.start
    result = @manager.cancel_job(job.id)
    assert result
    assert_equal :cancelled, job.status
  end

  def test_cancel_nonexistent_job_returns_false
    result = @manager.cancel_job(999)
    refute result
  end

  def test_clear_completed_jobs
    @manager.add_job(name: 'task1.rb', path: '.', command: 'echo 1')
    @manager.add_job(name: 'task2.rb', path: '.', command: 'echo 2')

    @manager.jobs[0].start
    @manager.jobs[0].complete(exit_code: 0)

    @manager.clear_completed

    assert_equal 1, @manager.job_count
    assert_equal 'task2.rb', @manager.jobs.first.name
  end

  def test_status_bar_text
    @manager.add_job(name: 'task1.rb', path: '.', command: 'echo 1')
    @manager.add_job(name: 'task2.rb', path: '.', command: 'echo 2')

    @manager.jobs[0].start

    text = @manager.status_bar_text
    # "2 jobs: 1 running, 0 done" のような形式
    assert_match(/2 jobs/, text)
    assert_match(/1 running/, text)
    assert_match(/0 done/, text)
  end

  def test_has_jobs?
    refute @manager.has_jobs?
    @manager.add_job(name: 'task.rb', path: '.', command: 'echo 1')
    assert @manager.has_jobs?
  end

  def test_any_running?
    @manager.add_job(name: 'task.rb', path: '.', command: 'echo 1')
    refute @manager.any_running?
    @manager.jobs.first.start
    assert @manager.any_running?
  end
end
