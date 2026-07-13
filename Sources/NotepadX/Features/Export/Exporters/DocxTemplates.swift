import Foundation

/// DOCX 패키지를 구성하는 정적/준정적 OOXML 파트. 스펙 15절이 요구하는 최소 파일 목록을 그대로 만든다.
enum Templates {
    static let contentTypes = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
      <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
      <Default Extension="xml" ContentType="application/xml"/>
      <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
      <Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
      <Override PartName="/word/numbering.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml"/>
      <Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>
      <Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>
    </Types>
    """

    static let rootRels = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
      <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
      <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>
      <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>
    </Relationships>
    """

    static func coreProperties(title: String, author: String) -> String {
        let now = ISO8601DateFormatter().string(from: Date())
        let escapedTitle = title.isEmpty ? "NotepadX Document" : title
        let escapedAuthor = author.isEmpty ? "NotepadX" : author
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
          <dc:title>\(escapedTitle)</dc:title>
          <dc:creator>\(escapedAuthor)</dc:creator>
          <cp:lastModifiedBy>\(escapedAuthor)</cp:lastModifiedBy>
          <dcterms:created xsi:type="dcterms:W3CDTF">\(now)</dcterms:created>
          <dcterms:modified xsi:type="dcterms:W3CDTF">\(now)</dcterms:modified>
        </cp:coreProperties>
        """
    }

    static let appProperties = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties" xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes">
      <Application>NotepadX</Application>
      <AppVersion>1.0</AppVersion>
    </Properties>
    """

    static let styles = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
      <w:docDefaults>
        <w:rPrDefault><w:rPr><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri"/><w:sz w:val="22"/></w:rPr></w:rPrDefault>
      </w:docDefaults>
      <w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/></w:style>
      <w:style w:type="paragraph" w:styleId="Title"><w:name w:val="Title"/><w:basedOn w:val="Normal"/>
        <w:pPr><w:spacing w:after="240"/></w:pPr>
        <w:rPr><w:b/><w:sz w:val="56"/></w:rPr>
      </w:style>
      <w:style w:type="paragraph" w:styleId="Subtitle"><w:name w:val="Subtitle"/><w:basedOn w:val="Normal"/>
        <w:rPr><w:color w:val="666666"/><w:sz w:val="20"/><w:i/></w:rPr>
      </w:style>
      <w:style w:type="paragraph" w:styleId="Heading1"><w:name w:val="heading 1"/><w:basedOn w:val="Normal"/>
        <w:pPr><w:spacing w:before="360" w:after="160"/><w:outlineLvl w:val="0"/></w:pPr>
        <w:rPr><w:b/><w:sz w:val="40"/></w:rPr>
      </w:style>
      <w:style w:type="paragraph" w:styleId="Heading2"><w:name w:val="heading 2"/><w:basedOn w:val="Normal"/>
        <w:pPr><w:spacing w:before="320" w:after="140"/><w:outlineLvl w:val="1"/></w:pPr>
        <w:rPr><w:b/><w:sz w:val="34"/></w:rPr>
      </w:style>
      <w:style w:type="paragraph" w:styleId="Heading3"><w:name w:val="heading 3"/><w:basedOn w:val="Normal"/>
        <w:pPr><w:spacing w:before="280" w:after="120"/><w:outlineLvl w:val="2"/></w:pPr>
        <w:rPr><w:b/><w:sz w:val="28"/></w:rPr>
      </w:style>
      <w:style w:type="paragraph" w:styleId="Heading4"><w:name w:val="heading 4"/><w:basedOn w:val="Normal"/>
        <w:pPr><w:spacing w:before="240" w:after="100"/><w:outlineLvl w:val="3"/></w:pPr>
        <w:rPr><w:b/><w:sz w:val="26"/></w:rPr>
      </w:style>
      <w:style w:type="paragraph" w:styleId="Heading5"><w:name w:val="heading 5"/><w:basedOn w:val="Normal"/>
        <w:pPr><w:spacing w:before="220" w:after="90"/><w:outlineLvl w:val="4"/></w:pPr>
        <w:rPr><w:b/><w:sz w:val="24"/></w:rPr>
      </w:style>
      <w:style w:type="paragraph" w:styleId="Heading6"><w:name w:val="heading 6"/><w:basedOn w:val="Normal"/>
        <w:pPr><w:spacing w:before="200" w:after="80"/><w:outlineLvl w:val="5"/></w:pPr>
        <w:rPr><w:b/><w:i/><w:sz w:val="22"/></w:rPr>
      </w:style>
      <w:style w:type="paragraph" w:styleId="Quote"><w:name w:val="Quote"/><w:basedOn w:val="Normal"/>
        <w:pPr><w:ind w:left="360"/><w:pBdr><w:left w:val="single" w:sz="12" w:space="8" w:color="999999"/></w:pBdr></w:pPr>
        <w:rPr><w:i/><w:color w:val="555555"/></w:rPr>
      </w:style>
      <w:style w:type="character" w:styleId="Hyperlink"><w:name w:val="Hyperlink"/>
        <w:rPr><w:color w:val="0563C1"/><w:u w:val="single"/></w:rPr>
      </w:style>
    </w:styles>
    """

    static func document(body: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
          <w:body>
        \(body)
          </w:body>
        </w:document>
        """
    }

    /// abstractNumId 0 = 글머리 기호(레벨 0~8, 전부 "•"), abstractNumId 1 = 번호(레벨 0~8, 전부
    /// decimal "N."). 레벨이 깊어질수록 들여쓰기만 늘어나고 서식은 단순하게 통일했다 — Word 기본
    /// 다단계 목록처럼 레벨별로 로마자/영문자를 섞는 대신, 어떤 깊이든 확실하게 "진짜 번호 매기기"로
    /// 인식되는 쪽을 택했다. entries는 DocxExporter가 실제 만난 목록마다 하나씩 등록한 (numId,
    /// abstractNumId) 쌍으로, 서로 다른 목록은 항상 번호가 1부터 다시 시작한다.
    static func numbering(entries: [(numId: Int, abstractNumId: Int)]) -> String {
        func bulletLevel(_ ilvl: Int) -> String {
            let indent = 720 + ilvl * 360
            return """
            <w:lvl w:ilvl="\(ilvl)">
              <w:start w:val="1"/>
              <w:numFmt w:val="bullet"/>
              <w:lvlText w:val="\u{2022}"/>
              <w:lvlJc w:val="left"/>
              <w:pPr><w:ind w:left="\(indent)" w:hanging="360"/></w:pPr>
            </w:lvl>
            """
        }
        func decimalLevel(_ ilvl: Int) -> String {
            let indent = 720 + ilvl * 360
            return """
            <w:lvl w:ilvl="\(ilvl)">
              <w:start w:val="1"/>
              <w:numFmt w:val="decimal"/>
              <w:lvlText w:val="%\(ilvl + 1)."/>
              <w:lvlJc w:val="left"/>
              <w:pPr><w:ind w:left="\(indent)" w:hanging="360"/></w:pPr>
            </w:lvl>
            """
        }

        let bulletLevels = (0..<9).map(bulletLevel).joined()
        let decimalLevels = (0..<9).map(decimalLevel).joined()
        let numEntries = entries.map {
            "<w:num w:numId=\"\($0.numId)\"><w:abstractNumId w:val=\"\($0.abstractNumId)\"/></w:num>"
        }.joined()

        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:numbering xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:abstractNum w:abstractNumId="0">
            <w:multiLevelType w:val="multilevel"/>
            \(bulletLevels)
          </w:abstractNum>
          <w:abstractNum w:abstractNumId="1">
            <w:multiLevelType w:val="multilevel"/>
            \(decimalLevels)
          </w:abstractNum>
          \(numEntries)
        </w:numbering>
        """
    }
}
