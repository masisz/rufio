# frozen_string_literal: true

require 'zip'

module DocumentSearchFixtures
  def write_package(path, parts)
    Zip::OutputStream.open(path) do |zip|
      parts.each do |name, content|
        zip.put_next_entry(name)
        zip.write(content)
      end
    end
    path
  end

  def write_search_pdf(path)
    objects = [
      '<< /Type /Catalog /Pages 2 0 R >>',
      '<< /Type /Pages /Kids [3 0 R 5 0 R] /Count 2 >>',
      '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 600 800] /Resources << /Font << /F1 7 0 R >> >> /Contents 4 0 R >>',
      nil,
      '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 600 800] /Resources << /Font << /F1 7 0 R >> >> /Contents 6 0 R >>',
      nil,
      '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>'
    ]
    [3, 5].each_with_index do |index, page|
      content = "BT /F1 12 Tf 50 700 Td (#{page.zero? ? 'Overview' : 'Document needle PDF'}) Tj ET\n"
      objects[index] = "<< /Length #{content.bytesize} >>\nstream\n#{content}endstream"
    end
    pdf = "%PDF-1.4\n".b
    offsets = [0]
    objects.each_with_index do |object, index|
      offsets << pdf.bytesize
      pdf << "#{index + 1} 0 obj\n#{object}\nendobj\n"
    end
    xref = pdf.bytesize
    pdf << "xref\n0 #{objects.length + 1}\n0000000000 65535 f \n"
    offsets.drop(1).each { |offset| pdf << format('%010d 00000 n ', offset) << "\n" }
    pdf << "trailer\n<< /Size #{objects.length + 1} /Root 1 0 R >>\nstartxref\n#{xref}\n%%EOF\n"
    File.binwrite(path, pdf)
    path
  end

  def write_search_xlsx(path)
    write_package(path, {
      '[Content_Types].xml' => '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/><Override PartName="/xl/sharedStrings.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml"/></Types>',
      '_rels/.rels' => '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>',
      'xl/workbook.xml' => '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="売上" sheetId="1" r:id="rId1"/></sheets></workbook>',
      'xl/_rels/workbook.xml.rels' => '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/sharedStrings" Target="sharedStrings.xml"/></Relationships>',
      'xl/sharedStrings.xml' => '<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" count="1" uniqueCount="1"><si><r><t>検索</t></r><r><t>対象 needle</t></r></si></sst>',
      'xl/worksheets/sheet1.xml' => '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><dimension ref="B2:D3"/><sheetData><row r="2"><c r="B2" t="s"><v>0</v></c><c r="D2"><v>12345</v></c></row><row r="3"><c r="C3" t="inlineStr"><is><t>inline needle</t></is></c><c r="D3"><f>1+1</f><v>2</v></c></row></sheetData></worksheet>'
    })
  end

  def write_search_pptx(path)
    # リレーションの順序で表示順を決定。ファイル名の番号とは異なる。
    write_package(path, {
      'ppt/presentation.xml' => '<p:presentation xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><p:sldIdLst><p:sldId id="256" r:id="rId2"/><p:sldId id="257" r:id="rId1"/></p:sldIdLst></p:presentation>',
      'ppt/_rels/presentation.xml.rels' => '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Target="slides/slide9.xml" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide"/><Relationship Id="rId2" Target="slides/slide2.xml" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide"/></Relationships>',
      'ppt/slides/slide2.xml' => '<p:sld xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"><p:cSld><p:spTree><p:sp><p:txBody><a:p><a:r><a:t>日本語の</a:t></a:r><a:r><a:t>needle</a:t></a:r></a:p><a:p><a:r><a:t>次の段落</a:t></a:r></a:p></p:txBody></p:sp></p:spTree></p:cSld></p:sld>',
      'ppt/slides/slide9.xml' => '<p:sld xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"><p:cSld><p:spTree><p:sp><p:txBody><a:p><a:r><a:t>Second needle</a:t></a:r></a:p></p:txBody></p:sp></p:spTree></p:cSld></p:sld>'
    })
  end
end
