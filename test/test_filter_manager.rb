# frozen_string_literal: true

require_relative 'test_helper'
require_relative '../lib/rufio/filter_manager'

class TestFilterManager < Minitest::Test
  def setup
    @filter_manager = Rufio::FilterManager.new
    @sample_entries = [
      { name: 'foo.rb', type: 'file' },
      { name: 'bar.txt', type: 'file' },
      { name: 'baz', type: 'directory' },
      { name: 'foo_test.rb', type: 'file' },
      { name: 'README.md', type: 'file' }
    ]
  end

  def test_initial_state
    assert_equal false, @filter_manager.filter_mode
    assert_equal '', @filter_manager.filter_query
    assert_equal false, @filter_manager.filter_active?
  end

  def test_start_filter_mode
    result = @filter_manager.start_filter_mode(@sample_entries)

    assert_equal true, result
    assert_equal true, @filter_manager.filter_mode
    assert_equal '', @filter_manager.filter_query
    assert_equal true, @filter_manager.filter_active?
    assert_equal @sample_entries, @filter_manager.filtered_entries
  end

  def test_filter_applies_correctly
    @filter_manager.start_filter_mode(@sample_entries)

    # Simulate typing "foo"
    @filter_manager.instance_variable_set(:@filter_query, 'foo')
    filtered = @filter_manager.apply_filter

    assert_equal 2, filtered.length
    assert_includes filtered.map { |e| e[:name] }, 'foo.rb'
    assert_includes filtered.map { |e| e[:name] }, 'foo_test.rb'
  end

  def test_filter_case_insensitive
    @filter_manager.start_filter_mode(@sample_entries)

    # Test case insensitive
    @filter_manager.instance_variable_set(:@filter_query, 'FOO')
    filtered = @filter_manager.apply_filter

    assert_equal 2, filtered.length
  end

  def test_filter_partial_match
    @filter_manager.start_filter_mode(@sample_entries)

    # Test partial match
    @filter_manager.instance_variable_set(:@filter_query, 'ba')
    filtered = @filter_manager.apply_filter

    assert_equal 2, filtered.length  # bar.txt, baz
    assert_includes filtered.map { |e| e[:name] }, 'bar.txt'
    assert_includes filtered.map { |e| e[:name] }, 'baz'
  end

  def test_empty_query_returns_all
    @filter_manager.start_filter_mode(@sample_entries)

    @filter_manager.instance_variable_set(:@filter_query, '')
    filtered = @filter_manager.apply_filter

    assert_equal @sample_entries.length, filtered.length
  end

  def test_no_matches
    @filter_manager.start_filter_mode(@sample_entries)

    @filter_manager.instance_variable_set(:@filter_query, 'xyz')
    filtered = @filter_manager.apply_filter

    assert_equal 0, filtered.length
  end

  def test_handle_filter_input_printable
    @filter_manager.start_filter_mode(@sample_entries)

    # Type 'f'
    result = @filter_manager.handle_filter_input('f')
    assert_equal :continue, result
    assert_equal 'f', @filter_manager.filter_query

    # Type 'o'
    result = @filter_manager.handle_filter_input('o')
    assert_equal :continue, result
    assert_equal 'fo', @filter_manager.filter_query

    # Type 'o'
    result = @filter_manager.handle_filter_input('o')
    assert_equal :continue, result
    assert_equal 'foo', @filter_manager.filter_query
  end

  def test_handle_filter_input_backspace
    @filter_manager.start_filter_mode(@sample_entries)
    @filter_manager.instance_variable_set(:@filter_query, 'foo')

    # Backspace
    result = @filter_manager.handle_filter_input("\u007f")
    assert_equal :continue, result
    assert_equal 'fo', @filter_manager.filter_query
  end

  def test_handle_filter_input_backspace_when_empty
    @filter_manager.start_filter_mode(@sample_entries)

    # Backspace when query is empty
    result = @filter_manager.handle_filter_input("\u007f")
    assert_equal :backspace_exit, result
  end

  def test_handle_filter_input_escape
    @filter_manager.start_filter_mode(@sample_entries)
    @filter_manager.instance_variable_set(:@filter_query, 'foo')

    # ESC
    result = @filter_manager.handle_filter_input("\e")
    assert_equal :exit_clear, result
  end

  def test_handle_filter_input_enter
    @filter_manager.start_filter_mode(@sample_entries)
    @filter_manager.instance_variable_set(:@filter_query, 'foo')

    # Enter
    result = @filter_manager.handle_filter_input("\r")
    assert_equal :exit_keep, result
  end

  def test_handle_filter_input_japanese
    @filter_manager.start_filter_mode(@sample_entries)

    # Type Japanese character
    result = @filter_manager.handle_filter_input('あ')
    assert_equal :continue, result
    assert_equal 'あ', @filter_manager.filter_query
  end

  def test_clear_filter
    @filter_manager.start_filter_mode(@sample_entries)
    @filter_manager.instance_variable_set(:@filter_query, 'foo')
    @filter_manager.apply_filter

    @filter_manager.clear_filter

    assert_equal false, @filter_manager.filter_mode
    assert_equal '', @filter_manager.filter_query
    assert_equal [], @filter_manager.filtered_entries
    assert_equal false, @filter_manager.filter_active?
  end

  def test_exit_filter_mode_keep_filter
    @filter_manager.start_filter_mode(@sample_entries)
    @filter_manager.instance_variable_set(:@filter_query, 'foo')
    filtered = @filter_manager.apply_filter

    @filter_manager.exit_filter_mode_keep_filter

    assert_equal false, @filter_manager.filter_mode
    assert_equal 'foo', @filter_manager.filter_query
    assert_equal filtered, @filter_manager.filtered_entries
    assert_equal true, @filter_manager.filter_active?
  end

  def test_update_entries
    @filter_manager.start_filter_mode(@sample_entries)
    @filter_manager.instance_variable_set(:@filter_query, 'foo')
    @filter_manager.apply_filter

    # Update with new entries
    new_entries = [
      { name: 'foo_new.rb', type: 'file' },
      { name: 'bar_new.txt', type: 'file' }
    ]

    @filter_manager.update_entries(new_entries)

    # Filter should be reapplied
    filtered = @filter_manager.filtered_entries
    assert_equal 1, filtered.length
    assert_equal 'foo_new.rb', filtered.first[:name]
  end

  def test_restart_filter_mode
    @filter_manager.start_filter_mode(@sample_entries)
    @filter_manager.instance_variable_set(:@filter_query, 'foo')
    @filter_manager.apply_filter
    @filter_manager.exit_filter_mode_keep_filter

    # Restart filter mode
    @filter_manager.restart_filter_mode(@sample_entries)

    assert_equal true, @filter_manager.filter_mode
    assert_equal 'foo', @filter_manager.filter_query
  end

  def test_filter_active_when_filter_mode
    @filter_manager.start_filter_mode(@sample_entries)
    assert_equal true, @filter_manager.filter_active?
  end

  def test_filter_active_when_query_not_empty
    @filter_manager.instance_variable_set(:@filter_query, 'foo')
    assert_equal true, @filter_manager.filter_active?
  end

  def test_filter_not_active_when_both_false
    assert_equal false, @filter_manager.filter_active?
  end
end
