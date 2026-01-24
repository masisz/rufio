# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/rufio/job_mode'
require_relative '../lib/rufio/job_manager'
require_relative '../lib/rufio/notification_manager'

class TestJobMode < Minitest::Test
  def setup
    @notification_manager = Rufio::NotificationManager.new
    @job_manager = Rufio::JobManager.new(notification_manager: @notification_manager)
    @job_mode = Rufio::JobMode.new(job_manager: @job_manager)
  end

  def test_initial_state_is_not_active
    refute @job_mode.active?
  end

  def test_activate_sets_active
    @job_mode.activate
    assert @job_mode.active?
  end

  def test_deactivate_clears_active
    @job_mode.activate
    @job_mode.deactivate
    refute @job_mode.active?
  end

  def test_initial_selected_index_is_zero
    assert_equal 0, @job_mode.selected_index
  end

  def test_move_down_increments_index
    add_sample_jobs(3)
    @job_mode.activate
    @job_mode.move_down
    assert_equal 1, @job_mode.selected_index
  end

  def test_move_down_does_not_exceed_job_count
    add_sample_jobs(2)
    @job_mode.activate
    @job_mode.move_down
    @job_mode.move_down
    @job_mode.move_down
    assert_equal 1, @job_mode.selected_index  # 最大は1（0-indexed）
  end

  def test_move_up_decrements_index
    add_sample_jobs(3)
    @job_mode.activate
    @job_mode.move_down
    @job_mode.move_down
    @job_mode.move_up
    assert_equal 1, @job_mode.selected_index
  end

  def test_move_up_does_not_go_below_zero
    add_sample_jobs(3)
    @job_mode.activate
    @job_mode.move_up
    @job_mode.move_up
    assert_equal 0, @job_mode.selected_index
  end

  def test_selected_job_returns_current_job
    add_sample_jobs(3)
    @job_mode.activate
    @job_mode.move_down
    job = @job_mode.selected_job
    assert_equal 'task2.rb', job.name
  end

  def test_selected_job_returns_nil_when_no_jobs
    @job_mode.activate
    assert_nil @job_mode.selected_job
  end

  def test_cancel_selected_job
    add_sample_jobs(2)
    @job_manager.jobs[0].start
    @job_mode.activate
    result = @job_mode.cancel_selected_job
    assert result
    assert_equal :cancelled, @job_manager.jobs[0].status
  end

  def test_cancel_selected_job_returns_false_when_no_jobs
    @job_mode.activate
    result = @job_mode.cancel_selected_job
    refute result
  end

  def test_handle_key_j_moves_down
    add_sample_jobs(3)
    @job_mode.activate
    result = @job_mode.handle_key('j')
    assert result
    assert_equal 1, @job_mode.selected_index
  end

  def test_handle_key_k_moves_up
    add_sample_jobs(3)
    @job_mode.activate
    @job_mode.move_down
    result = @job_mode.handle_key('k')
    assert result
    assert_equal 0, @job_mode.selected_index
  end

  def test_handle_key_x_cancels_job
    add_sample_jobs(2)
    @job_manager.jobs[0].start
    @job_mode.activate
    result = @job_mode.handle_key('x')
    assert result
    assert_equal :cancelled, @job_manager.jobs[0].status
  end

  def test_handle_key_escape_deactivates
    @job_mode.activate
    result = @job_mode.handle_key("\e")
    assert_equal :exit, result
    refute @job_mode.active?
  end

  def test_handle_key_space_shows_log
    add_sample_jobs(1)
    @job_mode.activate
    result = @job_mode.handle_key(' ')
    assert_equal :show_log, result
  end

  def test_log_mode_active
    add_sample_jobs(1)
    @job_mode.activate
    @job_mode.enter_log_mode
    assert @job_mode.log_mode?
  end

  def test_exit_log_mode
    add_sample_jobs(1)
    @job_mode.activate
    @job_mode.enter_log_mode
    @job_mode.exit_log_mode
    refute @job_mode.log_mode?
  end

  def test_move_to_top
    add_sample_jobs(5)
    @job_mode.activate
    @job_mode.move_down
    @job_mode.move_down
    @job_mode.move_to_top
    assert_equal 0, @job_mode.selected_index
  end

  def test_move_to_bottom
    add_sample_jobs(5)
    @job_mode.activate
    @job_mode.move_to_bottom
    assert_equal 4, @job_mode.selected_index
  end

  private

  def add_sample_jobs(count)
    count.times do |i|
      @job_manager.add_job(
        name: "task#{i + 1}.rb",
        path: './src',
        command: "ruby task#{i + 1}.rb"
      )
    end
  end
end
