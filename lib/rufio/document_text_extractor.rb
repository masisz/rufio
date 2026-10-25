# frozen_string_literal: true

require 'pdf/reader'
require 'csv'
require 'base64'
require 'roo'
require 'zip'
require 'nokogiri'
require 'pathname'
require 'uri'

module Rufio
  # 文書内の文字列を、元文書の位置情報付きで列挙する。外部コマンドは実行しない。
  class DocumentTextExtractor
    class ExtractionError < StandardError; end

    EXTENSIONS = %w[.pdf .xlsx .pptx].freeze
    DRAWING_NS = 'http://schemas.openxmlformats.org/drawingml/2006/main'
    PART_URI_PARSER = URI::RFC2396_Parser.new

    def supported?(path)
      EXTENSIONS.include?(File.extname(path).downcase)
    end

    def each_record(path)
      return enum_for(:each_record, path) unless block_given?

      case File.extname(path).downcase
      when '.pdf' then each_pdf_record(path) { |record| yield record }
      when '.xlsx' then each_excel_record(path) { |record| yield record }
      when '.pptx' then each_powerpoint_record(path) { |record| yield record }
      else raise ExtractionError, "Unsupported document: #{File.extname(path)}"
      end
    rescue ExtractionError
      raise
    rescue StandardError => e
      raise ExtractionError, "#{File.basename(path)}: #{e.message}"
    end

    private

    def each_pdf_record(path)
      File.open(path, 'rb') do |io|
        reader = PDF::Reader.new(io)
        reader.pages.each_with_index do |page, index|
          page.text.each_line do |text|
            next if text.strip.empty?

            yield(text: text.chomp, document_type: :pdf, page: index + 1, location: "Page #{index + 1}")
          end
        end
      end
    end

    def each_excel_record(path)
      workbook = Roo::Excelx.new(path)
      workbook.sheets.each do |name|
        workbook.sheet(name).each_row_streaming do |row|
          row.compact.each do |cell|
            value = cell.value
            next if value.nil? || value.to_s.empty?

            row_number, column = cell.coordinate
            address = "#{Roo::Utils.number_to_letter(column)}#{row_number}"
            yield(text: value.to_s, document_type: :xlsx, sheet: name, cell: address, location: "#{name}!#{address}")
          end
        end
      end
    ensure
      workbook.close if workbook
    end

    def read_xml(zip, part)
      entry = zip.find_entry(part)
      raise ExtractionError, "Missing document part: #{part}" unless entry

      xml = entry.get_input_stream { |stream| stream.read }
      Nokogiri::XML(xml) { |config| config.strict.nonet }
    end

    def each_powerpoint_record(path)
      Zip::File.open(path) do |zip|
        presentation = read_xml(zip, 'ppt/presentation.xml')
        relationships = read_xml(zip, 'ppt/_rels/presentation.xml.rels')
        slides = relationships.xpath('//*[local-name()="Relationship"]').each_with_object({}) do |node, result|
          next unless node['Type'].to_s.end_with?('/slide') && node['TargetMode'] != 'External'

          target = PART_URI_PARSER.unescape(node['Target'].to_s)
          part = target.start_with?('/') ? target.delete_prefix('/') : "ppt/#{target}"
          part = Pathname.new(part).cleanpath.to_s
          raise ExtractionError, 'Invalid slide path' unless part.start_with?('ppt/')

          result[node['Id']] = part
        end
        presentation.xpath('//*[local-name()="sldIdLst"]/*[local-name()="sldId"]').each_with_index do |node, index|
          relationship = node.attribute_nodes.find { |attribute| attribute.name == 'id' && attribute.namespace }
          part = slides[relationship&.value]
          raise ExtractionError, 'Missing slide relationship' unless part

          slide = read_xml(zip, part)
          slide.xpath('//a:p', 'a' => DRAWING_NS).each do |paragraph|
            text = paragraph.xpath('.//a:t | .//a:br', 'a' => DRAWING_NS).map do |fragment|
              fragment.name == 'br' ? "\n" : fragment.text
            end.join
            next if text.strip.empty?

            yield(text: text, document_type: :pptx, slide: index + 1, location: "Slide #{index + 1}")
          end
        end
      end
    end
  end

  # 検索語を変えるたびに文書を再解析しないための、容量制限付きメモリキャッシュ。
  # 完了した抽出のみ保持し、更新・置換されたファイルは再抽出する。
  class DocumentTextCache
    def initialize(extractor: DocumentTextExtractor.new, max_entries: 64, max_bytes: 16 * 1024 * 1024)
      @extractor = extractor
      @max_entries = max_entries
      @max_bytes = max_bytes
      @cache = {}
    end

    def each_record(path)
      return enum_for(:each_record, path) unless block_given?

      key = File.expand_path(path)
      before = signature(path)
      cached = @cache.delete(key)
      if cached && cached[:signature] == before
        @cache[key] = cached
        cached[:records].each { |record| yield record }
        return
      end

      records = []
      bytes = 0
      @extractor.each_record(path) do |record|
        record = record.merge(search_text: record[:text].downcase).transform_values do |value|
          value.is_a?(String) ? value.dup.freeze : value
        end.freeze
        bytes += record.values.sum { |value| value.is_a?(String) ? value.bytesize : 16 } + 64
        if bytes <= @max_bytes
          records << record if records
        else
          records = nil
        end
        yield record
      end
      return unless records && @max_entries.positive? && signature(path) == before

      @cache.shift while !@cache.empty? && (@cache.length >= @max_entries || cache_bytes + bytes > @max_bytes)
      @cache[key] = { signature: before, records: records.freeze, bytes: bytes }
    end

    private

    def cache_bytes
      @cache.values.sum { |entry| entry[:bytes] }
    end

    def signature(path)
      stat = File.stat(path)
      [stat.dev, stat.ino, stat.size, stat.mtime, stat.ctime]
    end
  end
end
