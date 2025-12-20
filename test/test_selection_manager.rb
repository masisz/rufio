# frozen_string_literal: true

require_relative 'test_helper'
require_relative '../lib/rufio/selection_manager'

class TestSelectionManager < Minitest::Test
  def setup
    @manager = Rufio::SelectionManager.new
    @sample_entries = [
      { name: 'foo.rb', type: 'file' },
      { name: 'bar.txt', type: 'file' },
      { name: 'baz', type: 'directory' }
    ]
  end

  def test_initial_state
    assert_equal [], @manager.selected_items
    assert_equal true, @manager.empty?
    assert_equal false, @manager.any?
    assert_equal 0, @manager.count
  end

  def test_toggle_selection_select
    entry = @sample_entries.first

    result = @manager.toggle_selection(entry)

    assert_equal true, result
    assert_equal ['foo.rb'], @manager.selected_items
    assert_equal true, @manager.selected?('foo.rb')
  end

  def test_toggle_selection_unselect
    entry = @sample_entries.first
    @manager.toggle_selection(entry)

    # Toggle again to unselect
    result = @manager.toggle_selection(entry)

    assert_equal false, result
    assert_equal [], @manager.selected_items
    assert_equal false, @manager.selected?('foo.rb')
  end

  def test_toggle_selection_multiple
    @manager.toggle_selection(@sample_entries[0])
    @manager.toggle_selection(@sample_entries[1])

    assert_equal 2, @manager.count
    assert_equal true, @manager.selected?('foo.rb')
    assert_equal true, @manager.selected?('bar.txt')
    assert_equal false, @manager.selected?('baz')
  end

  def test_toggle_selection_nil_entry
    result = @manager.toggle_selection(nil)

    assert_equal false, result
    assert_equal [], @manager.selected_items
  end

  def test_selected?
    @manager.add('foo.rb')

    assert_equal true, @manager.selected?('foo.rb')
    assert_equal false, @manager.selected?('bar.txt')
  end

  def test_selected_items_returns_copy
    @manager.add('foo.rb')
    items = @manager.selected_items
    items << 'bar.txt'

    # Original should not be modified
    assert_equal ['foo.rb'], @manager.selected_items
  end

  def test_clear
    @manager.add('foo.rb')
    @manager.add('bar.txt')
    @manager.clear

    assert_equal [], @manager.selected_items
    assert_equal true, @manager.empty?
  end

  def test_any?
    assert_equal false, @manager.any?

    @manager.add('foo.rb')
    assert_equal true, @manager.any?
  end

  def test_count
    assert_equal 0, @manager.count

    @manager.add('foo.rb')
    assert_equal 1, @manager.count

    @manager.add('bar.txt')
    assert_equal 2, @manager.count
  end

  def test_add
    @manager.add('foo.rb')

    assert_equal ['foo.rb'], @manager.selected_items
    assert_equal true, @manager.selected?('foo.rb')
  end

  def test_add_duplicate
    @manager.add('foo.rb')
    @manager.add('foo.rb')

    # Should not add duplicates
    assert_equal ['foo.rb'], @manager.selected_items
    assert_equal 1, @manager.count
  end

  def test_remove
    @manager.add('foo.rb')
    @manager.add('bar.txt')

    @manager.remove('foo.rb')

    assert_equal ['bar.txt'], @manager.selected_items
    assert_equal false, @manager.selected?('foo.rb')
  end

  def test_remove_nonexistent
    @manager.add('foo.rb')
    @manager.remove('nonexistent.txt')

    # Should not affect existing selections
    assert_equal ['foo.rb'], @manager.selected_items
  end

  def test_select_multiple
    items = ['foo.rb', 'bar.txt', 'baz']
    @manager.select_multiple(items)

    assert_equal 3, @manager.count
    assert_equal true, @manager.selected?('foo.rb')
    assert_equal true, @manager.selected?('bar.txt')
    assert_equal true, @manager.selected?('baz')
  end

  def test_select_multiple_with_duplicates
    @manager.add('foo.rb')
    @manager.select_multiple(['foo.rb', 'bar.txt'])

    # Should not add duplicates
    assert_equal 2, @manager.count
    assert_equal true, @manager.selected?('foo.rb')
    assert_equal true, @manager.selected?('bar.txt')
  end

  def test_empty?
    assert_equal true, @manager.empty?

    @manager.add('foo.rb')
    assert_equal false, @manager.empty?

    @manager.clear
    assert_equal true, @manager.empty?
  end

  def test_workflow
    # Typical workflow: select multiple items, then clear
    @manager.toggle_selection(@sample_entries[0])
    @manager.toggle_selection(@sample_entries[1])

    assert_equal 2, @manager.count

    # Unselect one
    @manager.toggle_selection(@sample_entries[0])
    assert_equal 1, @manager.count

    # Add more
    @manager.add('another.txt')
    assert_equal 2, @manager.count

    # Clear all
    @manager.clear
    assert_equal 0, @manager.count
    assert_equal true, @manager.empty?
  end
end
