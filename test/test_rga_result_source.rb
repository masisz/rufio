# frozen_string_literal: true

require_relative 'test_helper'
require 'minitest/autorun'
require 'rbconfig'

# F の rga 出力を FuzzySearchSession の候補としてストリーミングする。
class TestRgaResultSource < Minitest::Test
  def setup
    @root = Dir.mktmpdir('rufio_rga_source')
  end

  def teardown
    FileUtils.rm_rf(@root)
  end

  def ruby_command(script)
    [RbConfig.ruby, '-e', script]
  end

  def collect(source, cancelled: -> { false })
    batches = []
    errors = []
    source.each_batch(cancelled: cancelled, on_error: ->(message) { errors << message }) { |batch| batches << batch }
    [batches.flatten, errors]
  end

  def test_default_command_separates_query_from_options
    source = Rufio::RgaResultSource.new('--pre=evil', @root)
    command = source.command
    assert_equal 'rga', command.first
    assert_includes command, '--line-number'
    assert_includes command, '--with-filename'
    assert_equal ['--', '--pre=evil', '.'], command.last(3)
  end

  def test_parses_path_line_and_text
    script = 'puts "lib/a.rb:3:  def hello"; puts "b c.txt:12:x:y"'
    source = Rufio::RgaResultSource.new('hello', @root, command: ruby_command(script))
    entries, errors = collect(source)
    assert_empty errors
    assert_equal [
      { text: 'lib/a.rb:3:  def hello', path: File.join(@root, 'lib/a.rb'), line_number: 3 },
      { text: 'b c.txt:12:x:y', path: File.join(@root, 'b c.txt'), line_number: 12 }
    ], entries
  end

  def test_strips_dot_slash_and_skips_unparsable_lines
    script = 'puts "./a.txt:1:one"; puts "no line number here"; puts ""'
    source = Rufio::RgaResultSource.new('one', @root, command: ruby_command(script))
    entries, = collect(source)
    assert_equal [{ text: 'a.txt:1:one', path: File.join(@root, 'a.txt'), line_number: 1 }], entries
  end

  def test_scrubs_invalid_utf8_in_label_but_keeps_path_bytes
    script = '$stdout.binmode; $stdout.write("bad\xFF.txt:2:caf\xE9\n")'
    source = Rufio::RgaResultSource.new('caf', @root, command: ruby_command(script))
    entries, = collect(source)
    assert_equal 1, entries.length
    assert entries.first[:text].valid_encoding?
    assert_equal 2, entries.first[:line_number]
    assert_equal "bad\xFF.txt".b, File.basename(entries.first[:path]).b
  end

  def test_batches_large_output
    script = '600.times { |i| puts "f#{i}.txt:1:x" }'
    source = Rufio::RgaResultSource.new('x', @root, command: ruby_command(script))
    batches = []
    source.each_batch(cancelled: -> { false }, on_error: ->(_) {}) { |batch| batches << batch }
    assert_equal 600, batches.sum(&:length)
    assert batches.all? { |batch| batch.length <= Rufio::RgaResultSource::BATCH_SIZE }
  end

  def test_reports_failed_command
    source = Rufio::RgaResultSource.new('x', @root, command: ['rufio-command-that-does-not-exist'])
    entries, errors = collect(source)
    assert_empty entries
    assert_equal 1, errors.length
  end

  def test_cancellation_stops_silent_long_running_process
    script = '$stdout.sync = true; puts "a.txt:1:x"; sleep 30'
    source = Rufio::RgaResultSource.new('x', @root, command: ruby_command(script))
    cancelled = false
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    worker = Thread.new do
      source.each_batch(cancelled: -> { cancelled }, on_error: ->(_) {}) { |_| cancelled = true }
    end
    assert worker.join(5), 'source did not stop after cancellation'
    assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 5
  end

  def test_session_runs_source_and_filters_lines
    script = 'puts "a.txt:1:alpha"; puts "b.txt:2:beta"'
    source = Rufio::RgaResultSource.new('a', @root, command: ruby_command(script))
    session = Rufio::FuzzySearchSession.new(source: source, native: false).start
    session.update_query('bet')
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
    loop do
      session.poll
      state = session.snapshot
      break if state.query == 'bet' && !state.scanning && !state.searching
      flunk 'session did not finish' if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      sleep 0.005
    end
    assert_equal [2], session.snapshot.results.map { |result| result[:entry][:line_number] }
  ensure
    session&.close
  end
end
