# frozen_string_literal: true

require_relative 'test_helper'
require 'minitest/autorun'
require_relative '../lib/rufio/document_text_extractor'
require_relative 'support/document_search_fixtures'

class TestDocumentTextExtractor < Minitest::Test
  include DocumentSearchFixtures

  def setup
    @root = Dir.mktmpdir('rufio-documents')
    @extractor = Rufio::DocumentTextExtractor.new
  end

  def teardown
    FileUtils.rm_rf(@root)
  end

  def test_pdf_text_and_page_numbers
    records = @extractor.each_record(write_search_pdf(File.join(@root, 'sample.pdf'))).to_a
    match = records.find { |record| record[:text].include?('needle') }
    assert_equal 'Page 2', match[:location]
    assert_equal 2, match[:page]
    assert_equal :pdf, match[:document_type]
  end

  def test_excel_shared_inline_strings_numbers_and_cached_formulas
    records = @extractor.each_record(write_search_xlsx(File.join(@root, 'sample.xlsx'))).to_a
    cell = records.find { |record| record[:cell] == 'B2' }
    assert_equal '検索対象 needle', cell[:text]
    assert_equal '売上!B2', cell[:location]
    assert_equal '売上', cell[:sheet]
    assert_equal 'inline needle', records.find { |record| record[:cell] == 'C3' }[:text]
    assert_equal '12345', records.find { |record| record[:cell] == 'D2' }[:text]
    assert_equal '2', records.find { |record| record[:cell] == 'D3' }[:text]
  end

  def test_pdf_unicode_text_is_extracted_as_utf8
    path = write_unicode_search_pdf(File.join(@root, 'japanese.pdf'))
    text = @extractor.each_record(path).map { |record| record[:text] }.join
    assert_includes text, '日本語needle'
    assert_equal Encoding::UTF_8, text.encoding
  end

  def test_powerpoint_slide_order_and_split_text_runs
    records = @extractor.each_record(write_search_pptx(File.join(@root, 'sample.pptx'))).to_a
    first = records.find { |record| record[:text].include?('日本語') }
    assert_equal '日本語のneedle', first[:text]
    assert_equal 'Slide 1', first[:location]
    assert_equal 1, first[:slide]
    assert_equal 'Slide 2', records.find { |record| record[:text] == 'Second needle' }[:location]
    assert records.any? { |record| record[:text] == '次の段落' }
  end

  def test_corrupt_documents_raise_a_document_error
    %w[pdf xlsx pptx].each do |extension|
      path = File.join(@root, "broken.#{extension}")
      File.write(path, 'broken file')
      assert_raises(Rufio::DocumentTextExtractor::ExtractionError) { @extractor.each_record(path).to_a }
    end
    refute @extractor.supported?('legacy.ppt')
    refute @extractor.supported?('legacy.xls')
    assert @extractor.supported?('REPORT.PDF')
  end

  def test_cache_reuses_extraction_and_invalidates_changed_files
    path = File.join(@root, 'sample.pdf')
    File.write(path, 'first')
    calls = 0
    fake = Object.new
    fake.define_singleton_method(:each_record) do |file, &block|
      calls += 1
      block.call(text: File.read(file), location: 'Page 1')
    end
    cache = Rufio::DocumentTextCache.new(extractor: fake)
    assert_equal 'first', cache.each_record(path).to_a.first[:text]
    assert_equal 'first', cache.each_record(path).to_a.first[:text]
    assert_equal 1, calls
    File.write(path, 'updated document')
    assert_equal 'updated document', cache.each_record(path).to_a.first[:text]
    assert_equal 2, calls
  end

  def test_cache_evicts_old_entries_and_does_not_keep_oversized_documents
    calls = 0
    fake = Object.new
    fake.define_singleton_method(:each_record) { |file, &block| calls += 1; block.call(text: File.read(file)) }
    cache = Rufio::DocumentTextCache.new(extractor: fake, max_entries: 1, max_bytes: 512)
    a = File.join(@root, 'a.pdf')
    b = File.join(@root, 'b.pdf')
    File.write(a, 'a')
    File.write(b, 'b')
    [a, b, a].each { |file| cache.each_record(file).to_a }
    assert_equal 3, calls
    File.write(a, 'x' * 1024)
    2.times { assert_equal 1024, cache.each_record(a).to_a.first[:text].length }
    assert_equal 5, calls
  end

  def test_cache_does_not_store_partial_or_changed_extractions
    path = File.join(@root, 'changing.pdf')
    File.write(path, 'before')
    calls = 0
    fake = Object.new
    fake.define_singleton_method(:each_record) do |file, &block|
      calls += 1
      block.call(text: File.read(file))
      if calls == 1
        raise Rufio::DocumentTextExtractor::ExtractionError, 'interrupted extraction'
      elsif calls == 2
        File.write(file, 'changed during extraction')
      end
    end
    cache = Rufio::DocumentTextCache.new(extractor: fake)
    assert_raises(Rufio::DocumentTextExtractor::ExtractionError) { cache.each_record(path).to_a }
    cache.each_record(path).to_a
    assert_equal 'changed during extraction', cache.each_record(path).to_a.first[:text]
    assert_equal 3, calls
    cache.each_record(path).to_a
    assert_equal 3, calls
  end
end
