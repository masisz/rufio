# frozen_string_literal: true

require_relative 'test_helper'
require 'minitest/autorun'
require 'timeout'
require_relative 'support/document_search_fixtures'

class TestGlobalDocumentSearch < Minitest::Test
  include DocumentSearchFixtures

  def setup
    @root = Dir.mktmpdir('rufio-global-documents')
    @search = Rufio::GlobalSearch.new
    write_search_pdf(File.join(@root, 'sample.pdf'))
    write_search_xlsx(File.join(@root, 'sample.xlsx'))
    write_search_pptx(File.join(@root, 'sample.pptx'))
    File.write(File.join(@root, 'broken.pdf'), 'broken document')
    File.write(File.join(@root, 'plain.txt'), "plain needle\n")
  end

  def teardown
    @search.close
    FileUtils.rm_rf(@root)
  end

  def wait_for_scan
    Timeout.timeout(5) do
      while @search.scanning?
        @search.poll
        Thread.pass
      end
    end
  end

  def test_content_search_finds_documents_and_continues_after_corruption
    @search.open([{ name: 'Docs', path: @root }])
    @search.handle_key("\t")
    @search.handle_key('needle')
    wait_for_scan
    paths = @search.results.map { |result| File.basename(result[:path]) }.uniq.sort
    assert_equal %w[plain.txt sample.pdf sample.pptx sample.xlsx], paths
    assert_equal 1, @search.errors.length
    assert @search.errors.first.include?('broken.pdf')
    assert_equal 'Page 2', @search.results.find { |result| result[:document_type] == :pdf }[:location]
    assert_equal '売上!B2', @search.results.find { |result| result[:cell] == 'B2' }[:location]
    assert_equal 'Slide 1', @search.results.find { |result| result[:slide] == 1 }[:location]
    assert_equal 1, @search.results.find { |result| File.basename(result[:path]) == 'plain.txt' }[:line_number]

    screen = Rufio::Screen.new(100, 30)
    @search.draw(screen)
    text = (0...30).map { |row| Rufio::ColorHelper.strip_ansi(screen.row(row)) }.join("\n")
    assert_includes text, 'Page 2'
    assert_includes text, '売上!B2'
    assert_includes text, 'Slide 1'
  end

  def test_extension_exclusions_also_apply_to_documents
    Rufio::ConfigLoader.stub(:global_search_excluded_extensions, %w[.pdf .xlsx .pptx]) do
      @search.open([{ name: 'Docs', path: @root }])
      @search.handle_key("\t")
      @search.handle_key('needle')
      wait_for_scan
      assert_equal ['plain.txt'], @search.results.map { |result| File.basename(result[:path]) }
      assert_empty @search.errors
    end
  end
end
