# frozen_string_literal: true

# ReleaseFast build (outside the gem's bundled binaries):
# zig build-lib lib_zig/rufio_native/src/main.zig -dynamic -lc -O ReleaseFast \
#   -femit-bin=/tmp/librufio_fuzzy_release.dylib
# RUFIO_FUZZY_BENCH_LIBRARY=/tmp/librufio_fuzzy_release.dylib ruby test/benchmark_fuzzy_search.rb
# COUNTS=10000,100000,1000000 REPEATS=10 RUBY_MAX=10000 COMPARE_FZF=1
require 'json'
require 'open3'
require 'rbconfig'
require_relative '../lib/rufio/fuzzy_search'

def timed
  start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  result = yield
  [(Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000, result]
end

def summarize(values)
  sorted = values.sort
  { median_ms: sorted[sorted.length / 2].round(3), p95_ms: sorted[[(sorted.length * 0.95).ceil - 1, 0].max].round(3) }
end

if ARGV.first == '--worker'
  count = Integer(ARGV.fetch(1))
  engine = ARGV.fetch(2)
  queries = ['sctrl', 'src', '日本', 'xyzmissing', 'a']
  repeats = Integer(ENV.fetch('REPEATS', '10'))
  raise ArgumentError, 'REPEATS must be positive' unless repeats.positive?

  candidates = Array.new(count) do |i|
    case i % 4
    when 0 then "project_#{i % 137}/lib/search_controller_#{i}.rb"
    when 1 then "project_#{i % 137}/src/application_#{i}.rb"
    when 2 then "project_#{i % 137}/docs/日本語_#{i}.md"
    else "project_#{i % 137}/test/test_navigation_#{i}.rb"
    end
  end
  index = nil
  registration, = timed do
    unless engine == 'fzf'
      index = Rufio::FuzzySearch.new(native: engine == 'zig', library: ENV['RUFIO_FUZZY_BENCH_LIBRARY'])
      raise 'Native API unavailable' if engine == 'zig' && !index.native?

      candidates.each_slice(4096) { |batch| index.add(batch) }
    end
  end
  input = candidates.join("\n") + "\n" if engine == 'fzf'
  measurements = queries.map do |query|
    operation = proc do
      if engine == 'fzf'
        # Includes process launch, full candidate transfer and complete result drain;
        # this is not an isolated fzf matcher benchmark. Ignores user fzf options.
        _output, error, status = Open3.capture3({ 'FZF_DEFAULT_OPTS' => '', 'FZF_DEFAULT_OPTS_FILE' => '' },
                                               'fzf', '--filter', query, stdin_data: input)
        raise error unless [0, 1].include?(status.exitstatus)
      else
        index.query(query, limit: 100)
      end
    end
    operation.call # warm-up; registration and first-touch are not repeated-query timings
    values = Array.new(repeats) { timed { operation.call }.first }
    { query: query }.merge(summarize(values))
  end
  # ps is available on macOS/Linux; unavailable platforms report null.
  rss = begin
    unless engine == 'fzf' # its child has exited; parent RSS would be misleading
      output, status = Open3.capture2('ps', '-o', 'rss=', '-p', Process.pid.to_s)
      status.success? ? Integer(output.strip) : nil
    end
  rescue Errno::ENOENT, ArgumentError
    nil
  end
  puts JSON.generate(engine: engine, candidates: count, repeats: repeats, registration_ms: registration.round(3),
                     rss_kib: rss, timings: measurements)
  index&.close
else
  counts = ENV.fetch('COUNTS', '10000,100000,1000000').split(',').map { |n| Integer(n) }
  puts JSON.generate(ruby: RUBY_DESCRIPTION, platform: RUBY_PLATFORM,
                     note: 'Synthetic paths; Zig/Ruby warm queries include FFI and top-100 positions. fzf includes launch, transfer and all results; its RSS is not measured. RSS includes Ruby and input strings; no filesystem walk or UI.')
  counts.each do |count|
    engines = ['zig']
    engines << 'ruby' if count <= Integer(ENV.fetch('RUBY_MAX', '10000'))
    engines << 'fzf' if ENV['COMPARE_FZF'] == '1'
    engines.each do |engine|
      output, error, status = Open3.capture3(RbConfig.ruby, __FILE__, '--worker', count.to_s, engine)
      raise error unless status.success?

      puts output
    end
  end
end
