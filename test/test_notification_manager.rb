# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/rufio/notification_manager'

class TestNotificationManager < Minitest::Test
  def setup
    @manager = Rufio::NotificationManager.new
  end

  def test_initial_notifications_is_empty
    assert_equal 0, @manager.count
    assert_empty @manager.notifications
  end

  def test_add_success_notification
    @manager.add('setup.rb', :success, duration: 2.1)
    assert_equal 1, @manager.count
    notification = @manager.notifications.first
    assert_equal 'setup.rb', notification[:name]
    assert_equal :success, notification[:type]
    assert_equal 2.1, notification[:duration]
  end

  def test_add_error_notification
    @manager.add('test.py', :error, duration: 5.2, exit_code: 1)
    assert_equal 1, @manager.count
    notification = @manager.notifications.first
    assert_equal 'test.py', notification[:name]
    assert_equal :error, notification[:type]
    assert_equal 1, notification[:exit_code]
  end

  def test_max_three_notifications
    @manager.add('task1.rb', :success, duration: 1.0)
    @manager.add('task2.rb', :success, duration: 2.0)
    @manager.add('task3.rb', :success, duration: 3.0)
    @manager.add('task4.rb', :success, duration: 4.0)

    assert_equal 3, @manager.count
    # 最も古い通知（task1.rb）が削除される
    names = @manager.notifications.map { |n| n[:name] }
    refute_includes names, 'task1.rb'
    assert_includes names, 'task4.rb'
  end

  def test_expire_old_notifications
    # 既に期限切れの通知を手動で追加
    @manager.add('old_task.rb', :success, duration: 1.0)
    # 通知の作成時刻を過去に設定（4秒前）
    @manager.notifications.first[:created_at] = Time.now - 4

    @manager.expire_old_notifications

    assert_equal 0, @manager.count
  end

  def test_keep_fresh_notifications
    @manager.add('fresh_task.rb', :success, duration: 1.0)
    # 通知の作成時刻を1秒前に設定
    @manager.notifications.first[:created_at] = Time.now - 1

    @manager.expire_old_notifications

    assert_equal 1, @manager.count
  end

  def test_default_display_duration_is_3_seconds
    @manager.add('task.rb', :success, duration: 1.0)
    notification = @manager.notifications.first
    assert_equal 3, notification[:display_duration]
  end

  def test_custom_display_duration
    @manager.add('task.rb', :success, duration: 1.0, display_duration: 5)
    notification = @manager.notifications.first
    assert_equal 5, notification[:display_duration]
  end

  def test_success_status_text
    @manager.add('task.rb', :success, duration: 2.1)
    notification = @manager.notifications.first
    assert_equal 'Done (2.1s)', notification[:status_text]
  end

  def test_error_status_text
    @manager.add('task.rb', :error, duration: 5.2, exit_code: 1)
    notification = @manager.notifications.first
    assert_equal 'Failed (5.2s)', notification[:status_text]
  end

  def test_clear_all_notifications
    @manager.add('task1.rb', :success, duration: 1.0)
    @manager.add('task2.rb', :error, duration: 2.0, exit_code: 1)
    @manager.clear
    assert_equal 0, @manager.count
  end

  def test_notification_border_color_for_success
    @manager.add('task.rb', :success, duration: 1.0)
    notification = @manager.notifications.first
    assert_equal :green, notification[:border_color]
  end

  def test_notification_border_color_for_error
    @manager.add('task.rb', :error, duration: 1.0, exit_code: 1)
    notification = @manager.notifications.first
    assert_equal :red, notification[:border_color]
  end

  def test_notification_has_created_at
    before = Time.now
    @manager.add('task.rb', :success, duration: 1.0)
    after = Time.now
    notification = @manager.notifications.first
    assert notification[:created_at] >= before
    assert notification[:created_at] <= after
  end
end
