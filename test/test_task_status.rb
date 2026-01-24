# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/rufio/task_status'

class TestTaskStatus < Minitest::Test
  def setup
    @task = Rufio::TaskStatus.new(
      id: 1,
      name: 'build.rb',
      path: './src'
    )
  end

  def test_initial_status_is_waiting
    assert_equal :waiting, @task.status
  end

  def test_has_required_attributes
    assert_equal 1, @task.id
    assert_equal 'build.rb', @task.name
    assert_equal './src', @task.path
  end

  def test_initial_logs_is_empty
    assert_equal [], @task.logs
  end

  def test_initial_exit_code_is_nil
    assert_nil @task.exit_code
  end

  def test_start_sets_running_status_and_start_time
    @task.start
    assert_equal :running, @task.status
    refute_nil @task.start_time
  end

  def test_complete_sets_completed_status_and_end_time
    @task.start
    @task.complete(exit_code: 0)
    assert_equal :completed, @task.status
    refute_nil @task.end_time
    assert_equal 0, @task.exit_code
  end

  def test_fail_sets_failed_status
    @task.start
    @task.fail(exit_code: 1)
    assert_equal :failed, @task.status
    assert_equal 1, @task.exit_code
  end

  def test_duration_returns_nil_before_start
    assert_nil @task.duration
  end

  def test_duration_returns_elapsed_time_while_running
    @task.start
    sleep 0.1
    duration = @task.duration
    assert duration >= 0.1
    assert duration < 0.2
  end

  def test_duration_returns_total_time_after_completion
    @task.start
    sleep 0.1
    @task.complete(exit_code: 0)
    duration = @task.duration
    assert duration >= 0.1
    # 完了後は固定されるべき
    sleep 0.1
    assert_in_delta duration, @task.duration, 0.01
  end

  def test_append_log
    @task.append_log('Starting build...')
    @task.append_log('Compiling...')
    assert_equal 2, @task.logs.length
    assert_equal 'Starting build...', @task.logs[0]
    assert_equal 'Compiling...', @task.logs[1]
  end

  def test_running_predicate
    refute @task.running?
    @task.start
    assert @task.running?
    @task.complete(exit_code: 0)
    refute @task.running?
  end

  def test_completed_predicate
    refute @task.completed?
    @task.start
    refute @task.completed?
    @task.complete(exit_code: 0)
    assert @task.completed?
  end

  def test_failed_predicate
    refute @task.failed?
    @task.start
    @task.fail(exit_code: 1)
    assert @task.failed?
  end

  def test_status_icon_for_waiting
    assert_equal '⏸', @task.status_icon
  end

  def test_status_icon_for_running
    @task.start
    assert_equal '⚙', @task.status_icon
  end

  def test_status_icon_for_completed
    @task.start
    @task.complete(exit_code: 0)
    assert_equal '✓', @task.status_icon
  end

  def test_status_icon_for_failed
    @task.start
    @task.fail(exit_code: 1)
    assert_equal '✗', @task.status_icon
  end

  def test_formatted_duration_before_start
    assert_equal '', @task.formatted_duration
  end

  def test_formatted_duration_while_running
    @task.instance_variable_set(:@start_time, Time.now - 12.4)
    @task.instance_variable_set(:@status, :running)
    # 12.4s のような形式
    assert_match(/\d+\.\ds/, @task.formatted_duration)
  end

  def test_formatted_duration_after_completion
    @task.instance_variable_set(:@start_time, Time.now - 2.1)
    @task.instance_variable_set(:@end_time, Time.now)
    @task.instance_variable_set(:@status, :completed)
    assert_match(/\d+\.\ds/, @task.formatted_duration)
  end
end
