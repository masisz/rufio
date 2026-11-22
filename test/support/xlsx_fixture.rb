# frozen_string_literal: true

require 'zip'

# テスト用の最小 .xlsx ライタ（rubyzip だけで書く。外部ツールに依存しない）。
# 値はすべてインラインの文字列または数値セルとして書き、sharedStrings は使わない。
module XlsxFixture
  # @param path [String]
  # @param sheets [Array<Array(String, Array<Array>)>] [[シート名, 行の配列], ...]
  #   セルの値が Numeric なら数値セル、nil なら空セルとして書く
  def write_xlsx(path, sheets)
    Zip::OutputStream.open(path) do |zip|
      put(zip, '[Content_Types].xml', content_types(sheets.length))
      put(zip, '_rels/.rels', root_rels)
      put(zip, 'xl/workbook.xml', workbook(sheets))
      put(zip, 'xl/_rels/workbook.xml.rels', workbook_rels(sheets.length))
      put(zip, 'xl/styles.xml', styles)
      sheets.each_with_index do |(_, rows), index|
        put(zip, "xl/worksheets/sheet#{index + 1}.xml", worksheet(rows))
      end
    end
    path
  end

  # テスト用の最小 .ods ライタ（OpenDocument。roo は Roo::OpenOffice で読む）
  # @param sheets [Array<Array(String, Array<Array>)>]
  def write_ods(path, sheets)
    Zip::OutputStream.open(path) do |zip|
      zip.put_next_entry('mimetype')
      zip.write('application/vnd.oasis.opendocument.spreadsheet')
      put(zip, 'META-INF/manifest.xml', ods_manifest)
      put(zip, 'content.xml', ods_content(sheets))
    end
    path
  end

  private

  def ods_manifest
    '<manifest:manifest xmlns:manifest="urn:oasis:names:tc:opendocument:xmlns:manifest:1.0">' \
      '<manifest:file-entry manifest:full-path="/" ' \
      'manifest:media-type="application/vnd.oasis.opendocument.spreadsheet"/>' \
      '<manifest:file-entry manifest:full-path="content.xml" manifest:media-type="text/xml"/>' \
      '</manifest:manifest>'
  end

  def ods_content(sheets)
    tables = sheets.map do |name, rows|
      body = rows.map do |cells|
        columns = cells.map { |value| ods_cell(value) }.join
        "<table:table-row>#{columns}</table:table-row>"
      end.join
      %(<table:table table:name="#{escape(name)}">#{body}</table:table>)
    end.join

    '<office:document-content ' \
      'xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" ' \
      'xmlns:table="urn:oasis:names:tc:opendocument:xmlns:table:1.0" ' \
      'xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0">' \
      "<office:body><office:spreadsheet>#{tables}</office:spreadsheet></office:body>" \
      '</office:document-content>'
  end

  def ods_cell(value)
    return '<table:table-cell/>' if value.nil?

    if value.is_a?(Numeric)
      %(<table:table-cell office:value-type="float" office:value="#{value}">) +
        "<text:p>#{value}</text:p></table:table-cell>"
    else
      '<table:table-cell office:value-type="string">' \
        "<text:p>#{escape(value.to_s)}</text:p></table:table-cell>"
    end
  end

  def put(zip, name, body)
    zip.put_next_entry(name)
    zip.write(%(<?xml version="1.0" encoding="UTF-8"?>#{body}))
  end

  def content_types(count)
    overrides = (1..count).map do |i|
      %(<Override PartName="/xl/worksheets/sheet#{i}.xml" ) +
        %(ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>)
    end.join
    '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">' \
      '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>' \
      '<Default Extension="xml" ContentType="application/xml"/>' \
      '<Override PartName="/xl/workbook.xml" ' \
      'ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>' \
      '<Override PartName="/xl/styles.xml" ' \
      'ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>' \
      "#{overrides}</Types>"
  end

  def root_rels
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">' \
      '<Relationship Id="rId1" ' \
      'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" ' \
      'Target="xl/workbook.xml"/></Relationships>'
  end

  def workbook(sheets)
    entries = sheets.each_with_index.map do |(name, _), index|
      %(<sheet name="#{escape(name)}" sheetId="#{index + 1}" r:id="rId#{index + 1}"/>)
    end.join
    '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" ' \
      'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">' \
      "<sheets>#{entries}</sheets></workbook>"
  end

  def workbook_rels(count)
    entries = (1..count).map do |i|
      %(<Relationship Id="rId#{i}" ) +
        %(Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" ) +
        %(Target="worksheets/sheet#{i}.xml"/>)
    end.join
    styles = %(<Relationship Id="rId#{count + 1}" ) +
             %(Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" ) +
             %(Target="styles.xml"/>)
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">' \
      "#{entries}#{styles}</Relationships>"
  end

  # 数値セルは書式を参照するため、roo は styles.xml を要求する
  def styles
    '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">' \
      '<numFmts count="0"/><fonts count="1"><font/></fonts><fills count="1"><fill/></fills>' \
      '<borders count="1"><border/></borders><cellStyleXfs count="1"><xf/></cellStyleXfs>' \
      '<cellXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/></cellXfs>' \
      '</styleSheet>'
  end

  def worksheet(rows)
    body = rows.each_with_index.map do |cells, row_index|
      columns = cells.each_with_index.map { |value, column| cell(value, column, row_index + 1) }.compact.join
      %(<row r="#{row_index + 1}">#{columns}</row>)
    end.join
    '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">' \
      "<sheetData>#{body}</sheetData></worksheet>"
  end

  def cell(value, column, row)
    return nil if value.nil?

    reference = "#{column_name(column)}#{row}"
    if value.is_a?(Numeric)
      %(<c r="#{reference}"><v>#{value}</v></c>)
    else
      %(<c r="#{reference}" t="inlineStr"><is><t>#{escape(value.to_s)}</t></is></c>)
    end
  end

  def column_name(index)
    name = ''
    number = index
    loop do
      name = ((number % 26) + 65).chr + name
      number = number / 26 - 1
      break if number.negative?
    end
    name
  end

  def escape(text)
    text.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;').gsub('"', '&quot;')
  end
end
