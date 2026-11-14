# frozen_string_literal: true

require_relative 'test_fuzzy_search_session'

class TestFuzzySessionLifecycle < Minitest::Test
  Batches = TestFuzzySearchSession::Batches
  PausedSource = TestFuzzySearchSession::PausedSource
  GatedIndex = TestFuzzySearchSession::GatedIndex

  def setup
    @sessions = []
    @gates = []
  end

  def teardown
    @sessions.each(&:close)
    @gates.each { |gate| gate.release << true }
    @sessions.each { |search| assert search.wait(timeout: 3), 'Session leaked a worker' }
  end

  def session(source, **options)
    search = Rufio::FuzzySearchSession.new(source: source, native: false, **options)
    @sessions << search
    search.start
  end

  def settle(search)
    Timeout.timeout(3) do
      loop do
        search.poll
        break unless search.scanning? || search.searching?

        Thread.pass
      end
    end
  end

  # This notification is a scheduling barrier after publication, not a sleep.
  class ObservedSession < Rufio::FuzzySearchSession
    attr_reader :published

    def initialize(**options)
      super
      @published = Queue.new
    end

    private

    def publish(*args)
      super
      @published << args[0]
    end
  end

  def test_start_rejected_twice_does_not_close_a_running_session
    search = session(Batches.new(['alpha']))
    settle(search)
    assert_raises(IOError) { search.start }
    assert search.active?
    search.update_query('alp')
    settle(search)
    assert_equal ['alpha'], search.results.map { |r| r[:entry][:text] }
  end

  def test_result_published_before_poll_is_invalidated_by_new_input
    index = GatedIndex.new('beta')
    @gates << index
    search = ObservedSession.new(source: Batches.new(['alpha', 'beta']), index_factory: -> { index })
    @sessions << search
    search.start
    settle(search)
    search.update_query('alpha')
    target = search.generation
    Timeout.timeout(3) { loop { break if search.published.pop == target } }
    search.update_query('beta')
    Timeout.timeout(3) { index.entered.pop }
    search.poll
    assert_empty search.results
    assert search.searching?
    index.release << true
    settle(search)
    assert_equal ['beta'], search.results.map { |r| r[:entry][:text] }
  end

  def test_original_binary_path_is_immutable_and_distinct_from_display_label
    path = "/root/raw_\xff.rb".b
    text = +"raw_\uFFFD.rb"
    source = PausedSource.new([{ text: text, path: path }], [])
    @gates << source
    search = session(source)
    Timeout.timeout(3) { source.ready.pop }
    path.replace('changed')
    text.replace('changed')
    source.release << true
    settle(search)
    assert_equal "/root/raw_\xff.rb".b, search.results.first[:entry][:path]
    assert_equal "raw_\uFFFD.rb", search.results.first[:entry][:text]
    assert search.results.first[:entry][:path].frozen?
  end

  def test_empty_source_and_zero_limit_complete
    search = session(Batches.new)
    settle(search)
    assert_empty search.results
    assert_empty search.errors
    assert_equal 0, search.candidate_count
    another = session(Batches.new(['alpha', 'abc']), limit: 0)
    another.update_query('a')
    settle(another)
    assert_empty another.results
    assert_equal 2, another.total_matches
    assert_equal 2, another.candidate_count
  end
end
