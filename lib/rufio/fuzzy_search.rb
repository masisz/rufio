# frozen_string_literal: true

require 'fiddle'
require 'fiddle/import'
require 'thread'
require_relative 'native_scanner'
require_relative 'native_scanner_zig'

module Rufio
  # Persistent candidate index. No subprocesses; native and Ruby return the same
  # scores and UTF-8 byte offsets. A session serializes access to its native handle.
  # A query that extends the previous one (the previous query is a subsequence of it)
  # only scores the previous matches plus candidates added since; see #scanned.
  class FuzzySearch
    MAX_QUERY_BYTES = 1024
    MAX_CANDIDATE_BYTES = 65_536
    MAX_RESULTS = 10_000
    NEGATIVE = -(1 << 60)
    SEPARATORS = [47, 92, 95, 45, 46, 32].freeze

    attr_reader :total_matches

    # Candidates scored by the last query. nil when an older native library cannot report it.
    attr_reader :scanned

    def initialize(native: true, library: nil)
      @mutex = Mutex.new
      @closed = false
      @total_matches = 0
      @candidates = []
      @previous_query = nil
      @previous_ids = nil
      @previous_count = 0
      @scanned = 0
      if native && ENV['RUFIO_NATIVE_FUZZY'] != '0'
        @api = load_api(library || NativeScannerZigFFI.library_path)
        @handle = @api.core_fuzzy_create if @api
        raise NoMemoryError, 'Cannot create fuzzy index' if @handle == 0
        ObjectSpace.define_finalizer(self, self.class.finalizer(@api, @handle)) if @api
      end
    end

    def self.finalizer(api, handle)
      proc { api.core_fuzzy_destroy(handle) }
    end

    def native?
      !@api.nil?
    end

    def add(candidates)
      @mutex.synchronize do
        ensure_open!
        strings = candidates.map { |text| validate_text(text, MAX_CANDIDATE_BYTES) }
        if native?
          unless strings.empty?
            packed = strings.join("\0") + "\0"
            check_status(@api.core_fuzzy_add(@handle, packed, packed.bytesize))
          end
        else
          @candidates.concat(strings.map { |text| prepare(text) })
        end
      end
      self
    end

    def query(text, limit: 100)
      @mutex.synchronize do
        ensure_open!
        text = validate_text(text, MAX_QUERY_BYTES)
        raise ArgumentError, 'Invalid result limit' unless limit.is_a?(Integer) && limit.between?(0, MAX_RESULTS)

        native? ? query_native(text, limit) : query_ruby(text, limit)
      end
    end

    def close
      @mutex.synchronize do
        return if @closed

        if native?
          ObjectSpace.undefine_finalizer(self)
          @api.core_fuzzy_destroy(@handle)
        end
        @candidates.clear
        @closed = true
      end
    end

    private

    def ensure_open!
      raise IOError, 'Fuzzy index is closed' if @closed
    end

    def validate_text(text, max_bytes)
      raise ArgumentError, 'Expected UTF-8 text' unless text.is_a?(String)

      # Candidates are usually UTF-8 already; copying each one only to relabel it is wasted work.
      utf8 = text.encoding == Encoding::UTF_8 ? text : text.dup.force_encoding(Encoding::UTF_8)
      unless utf8.valid_encoding? && !utf8.include?("\0") && utf8.bytesize <= max_bytes
        raise ArgumentError, 'Invalid UTF-8, NUL, or text too long'
      end
      utf8
    end

    def load_api(path)
      return unless path && File.file?(path)

      Module.new do
        extend Fiddle::Importer
        dlload path
        extern 'uint64_t core_fuzzy_create()'
        extern 'int32_t core_fuzzy_add(uint64_t, const char*, size_t)'
        extern 'int32_t core_fuzzy_query(uint64_t, const char*, size_t, uint32_t)'
        extern 'void* core_fuzzy_results(uint64_t, void*)'
        extern 'void core_fuzzy_destroy(uint64_t)'
        begin
          extern 'uint64_t core_fuzzy_scanned(uint64_t)'
        rescue Fiddle::DLError
          nil # 1.6.0 development builds before narrowing
        end
      end
    rescue Fiddle::DLError
      nil
    end

    def check_status(status)
      raise ArgumentError, 'Native fuzzy search rejected input' if status == -1
      raise NoMemoryError, 'Native fuzzy search allocation failed' if status != 0
    end

    def query_native(text, limit)
      check_status(@api.core_fuzzy_query(@handle, text, text.bytesize, limit))
      length = Fiddle::Pointer.malloc(Fiddle::SIZEOF_SIZE_T, Fiddle::RUBY_FREE)
      pointer = @api.core_fuzzy_results(@handle, length)
      bytes = length[0, Fiddle::SIZEOF_SIZE_T].unpack1(Fiddle::SIZEOF_SIZE_T == 8 ? 'Q' : 'L')
      data = pointer.to_str(bytes)
      @scanned = @api.respond_to?(:core_fuzzy_scanned) ? @api.core_fuzzy_scanned(@handle) : nil
      @total_matches, count = data.unpack('Q<L<')
      offset = 12
      Array.new(count) do
        id, score, size = data.byteslice(offset, 20).unpack('Q<q<L<')
        positions = data.byteslice(offset + 20, size * 4).unpack('L<*')
        offset += 20 + size * 4
        { id: id, score: score, positions: positions }
      end
    end

    def fold(codepoint)
      codepoint.between?(65, 90) ? codepoint + 32 : codepoint
    end

    def prepare(text)
      chars = text.codepoints
      basename = (chars.rindex { |c| c == 47 || c == 92 } || -1) + 1
      bytes = 0
      offsets = chars.map do |char|
        position = bytes
        bytes += char.chr(Encoding::UTF_8).bytesize
        position
      end
      bonuses = chars.each_index.map do |i|
        boundary = i.zero? || SEPARATORS.include?(chars[i - 1]) ||
                   (chars[i - 1].between?(97, 122) && chars[i].between?(65, 90))
        16 + (i >= basename ? 8 : 0) + (boundary ? 8 : 0)
      end
      [chars.map { |c| fold(c) }, offsets, bonuses]
    end

    # Two rolling rows for scoring; only retained candidates need backtracking.
    def score(candidate, query, trace: false)
      chars, offsets, bonuses = candidate
      return [0, []] if query.empty?
      return if query.length > chars.length

      matched = 0
      chars.each do |char|
        matched += 1 if char == query[matched]
        break if matched == query.length
      end
      return unless matched == query.length

      previous = Array.new(chars.length, NEGATIVE)
      parents = []
      query.each_with_index do |char, row|
        current = Array.new(chars.length, NEGATIVE)
        parent = trace ? Array.new(chars.length, -1) : nil
        prefix_score = NEGATIVE
        prefix_index = -1
        chars.each_index do |i|
          if i >= 2 && previous[i - 2] != NEGATIVE && previous[i - 2] + i - 2 > prefix_score
            prefix_score = previous[i - 2] + i - 2
            prefix_index = i - 2
          end
          next unless chars[i] == char

          if row.zero?
            current[i] = bonuses[i] - i
          else
            value = prefix_score == NEGATIVE ? NEGATIVE : prefix_score - i + 1
            source = prefix_index
            if i > 0 && previous[i - 1] != NEGATIVE && previous[i - 1] + 24 > value
              value = previous[i - 1] + 24
              source = i - 1
            end
            next if value == NEGATIVE

            current[i] = value + bonuses[i]
            parent[i] = source if trace
          end
        end
        parents << parent if trace
        previous = current
      end
      best = previous.max
      return if best == NEGATIVE

      positions = []
      if trace
        index = previous.index(best)
        (query.length - 1).downto(0) do |row|
          positions << offsets[index]
          index = parents[row][index]
        end
        positions.reverse!
      end
      [best - chars.length + (query.length == chars.length ? 64 : 0), positions]
    end

    def subsequence?(small, large)
      matched = 0
      large.each { |char| matched += 1 if matched < small.length && char == small[matched] }
      matched == small.length
    end

    def query_ruby(text, limit)
      query = text.codepoints.map { |c| fold(c) }
      narrow = @previous_query && !query.empty? && subsequence?(@previous_query, query)
      ids = narrow ? @previous_ids + (@previous_count...@candidates.length).to_a : (0...@candidates.length)
      @scanned = ids.size
      @previous_query = nil
      matched_ids = []
      @total_matches = 0
      # Bounded sorted list: the fallback favors simplicity, while Zig uses a heap.
      best = []
      ids.each do |id|
        candidate = @candidates[id]
        matched = score(candidate, query)
        next unless matched

        matched_ids << id
        @total_matches += 1
        next if limit.zero?

        key = [-matched[0], id]
        at = best.bsearch_index { |item| ([-item[:score], item[:id]] <=> key) > 0 } || best.length
        next if at >= limit

        best.insert(at, { id: id, score: matched[0] })
        best.pop if best.length > limit
      end
      unless query.empty?
        @previous_query = query
        @previous_ids = matched_ids
        @previous_count = @candidates.length
      end
      best.each { |item| item[:positions] = score(@candidates[item[:id]], query, trace: true)[1] }
    end
  end
end
