# frozen_string_literal: true

# RUFIO_FUZZY_BENCH_LIBRARY=/tmp/librufio_fuzzy_release.dylib \
#   COUNTS=100000 REPEATS=3 ruby test/benchmark_fuzzy_session.rb
# REFRESH_INTERVAL=0 reproduces a full query after every indexing batch.
require 'json'
require 'timeout'
require_relative '../lib/rufio/fuzzy_search_session'

class FuzzyBenchmarkSource
  def initialize(rows)
    @rows = rows
  end

  def each_batch(cancelled:, on_error:)
    @rows.each_slice(256) do |batch|
      break if cancelled.call

      yield batch
    end
  end
end

class FuzzyBenchmarkIndex
  attr_reader :query_calls

  def initialize(library)
    @index = Rufio::FuzzySearch.new(library: library)
    raise 'Build a ReleaseFast library and set RUFIO_FUZZY_BENCH_LIBRARY' unless @index.native?

    @query_calls = 0
  end

  def add(rows)
    @index.add(rows)
  end

  def query(text, limit:)
    @query_calls += 1
    @index.query(text, limit: limit)
  end

  def total_matches
    @index.total_matches
  end

  def close
    @index.close
  end
end

def measure_session(rows, interval)
  index = nil
  source = FuzzyBenchmarkSource.new(rows)
  factory = -> { index = FuzzyBenchmarkIndex.new(ENV['RUFIO_FUZZY_BENCH_LIBRARY']) }
  session = Rufio::FuzzySearchSession.new(source: source, index_factory: factory, refresh_interval: interval)
  start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  session.start
  session.update_query('sctrl')
  first_result_ms = nil
  Timeout.timeout(60) do
    loop do
      session.poll
      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      first_result_ms ||= (now - start) * 1000 unless session.results.empty?
      break unless session.scanning? || session.searching?

      sleep 0.001
    end
  end
  elapsed = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000
  raise session.errors.join('; ') unless session.errors.empty?
  raise 'Incomplete index or result count' unless session.candidate_count == rows.length && session.total_matches == rows.length

  { first_result_ms: first_result_ms.round(3), complete_ms: elapsed.round(3), query_calls: index.query_calls }
ensure
  session&.close
  raise 'Session cleanup timed out' if session && !session.wait(timeout: 5)
end

interval = Float(ENV.fetch('REFRESH_INTERVAL', Rufio::FuzzySearchSession::REFRESH_INTERVAL.to_s))
repeats = Integer(ENV.fetch('REPEATS', '3'))
raise ArgumentError, 'REPEATS must be positive' unless repeats.positive?

puts JSON.generate(ruby: RUBY_DESCRIPTION, refresh_interval: interval,
                   note: 'Synthetic pre-generated paths; no disk scan or UI. Includes worker startup, indexing, queries and polling every 1ms.')
ENV.fetch('COUNTS', '100000').split(',').each do |value|
  count = Integer(value)
  raise ArgumentError, 'COUNTS must be positive' unless count.positive?

  rows = Array.new(count) { |i| "lib/search_controller_#{i}.rb" }
  samples = Array.new(repeats) { measure_session(rows, interval) }
  puts JSON.generate(candidates: count, samples: samples)
end
