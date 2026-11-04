import Foundation
import PDFKit
import UniformTypeIdentifiers

enum BookParseError: LocalizedError {
    case unsupported(String)
    case empty
    case unreadable

    var errorDescription: String? {
        switch self {
        case .unsupported(let ext):
            return "暂不支持 .\(ext) 格式，请先转换为 EPUB 或 TXT"
        case .empty:
            return "文件内容为空"
        case .unreadable:
            return "无法读取文件内容"
        }
    }
}

struct ParsedBook {
    var title: String
    var text: String
    var format: String
    var chapterTitles: [String]
}

enum BookParser {
    static func parse(url: URL) throws -> ParsedBook {
        let ext = url.pathExtension.lowercased()
        let title = url.deletingPathExtension().lastPathComponent

        switch ext {
        case "txt":
            let text = try readText(url: url)
            guard !text.isEmpty else { throw BookParseError.empty }
            return ParsedBook(title: title, text: text, format: "txt",
                              chapterTitles: extractTXTChapters(text))
        case "epub":
            return try parseEPUB(url: url, fallbackTitle: title)
        case "pdf":
            return try parsePDF(url: url, fallbackTitle: title)
        default:
            throw BookParseError.unsupported(ext.isEmpty ? "未知" : ext)
        }
    }

    // MARK: - TXT

    private static func readText(url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        guard !data.isEmpty else { throw BookParseError.empty }

        let gb18030 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        let encodings: [String.Encoding] = [
            .utf8, .utf16, .utf16LittleEndian, .utf16BigEndian, gb18030, .isoLatin1
        ]
        for enc in encodings {
            if let s = String(data: data, encoding: enc) { return normalize(s) }
        }
        return normalize(String(decoding: data, as: UTF8.self))
    }

    private static func normalize(_ s: String) -> String {
        s.replacingOccurrences(of: "\r\n", with: "\n")
         .replacingOccurrences(of: "\r", with: "\n")
         .replacingOccurrences(of: "\u{3000}", with: "  ")
    }

    private static let chapterPatterns = [
        #"^第[零一二三四五六七八九十百千万0-9]+[章回节卷篇]"#,
        #"^Chapter\s+\d+"#,
        #"^CHAPTER\s+\d+"#,
        #"^[0-9]{1,4}[、.．\s]"#
    ]

    private static func extractTXTChapters(_ text: String) -> [String] {
        let regexes = chapterPatterns.compactMap { try? NSRegularExpression(pattern: $0) }
        var titles: [String] = []
        text.enumerateLines { line, _ in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard (2...60).contains(trimmed.count) else { return }
            let range = NSRange(trimmed.startIndex..., in: trimmed)
            for r in regexes where r.firstMatch(in: trimmed, range: range) != nil {
                titles.append(trimmed)
                break
            }
        }
        return titles
    }

    // MARK: - EPUB

    private static func parseEPUB(url: URL, fallbackTitle: String) throws -> ParsedBook {
        let zip = try ZipReader(url: url)

        guard let containerData = zip.read("META-INF/container.xml"),
              let containerXML = String(data: containerData, encoding: .utf8),
              let opfPath = firstMatch(in: containerXML, pattern: #"full-path="([^"]+)""#) else {
            throw BookParseError.unreadable
        }

        guard let opfData = zip.read(opfPath),
              let opfXML = String(data: opfData, encoding: .utf8) else {
            throw BookParseError.unreadable
        }

        let baseDir = (opfPath as NSString).deletingLastPathComponent
        let bookTitle = firstMatch(in: opfXML, pattern: #"<dc:title[^>]*>([^<]+)</dc:title>"#)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? fallbackTitle

        var idToHref: [String: String] = [:]
        let itemRegex = try NSRegularExpression(pattern: #"<item[^>]*id="([^"]+)"[^>]*href="([^"]+)"[^>]*/?>"#)
        let nsOpf = opfXML as NSString
        itemRegex.enumerateMatches(in: opfXML, range: NSRange(location: 0, length: nsOpf.length)) { m, _, _ in
            guard let m = m, m.numberOfRanges >= 3 else { return }
            let id = nsOpf.substring(with: m.range(at: 1))
            let href = nsOpf.substring(with: m.range(at: 2))
            idToHref[id] = href
        }

        var orderedHrefs: [String] = []
        let spineRegex = try NSRegularExpression(pattern: #"<itemref[^>]*idref="([^"]+)""#)
        spineRegex.enumerateMatches(in: opfXML, range: NSRange(location: 0, length: nsOpf.length)) { m, _, _ in
            guard let m = m, m.numberOfRanges >= 2 else { return }
            let idref = nsOpf.substring(with: m.range(at: 1))
            if let href = idToHref[idref] { orderedHrefs.append(href) }
        }

        var chapters: [String] = []
        var allText = ""

        for href in orderedHrefs {
            let cleanHref = href.removingPercentEncoding ?? href
            let fullPath = baseDir.isEmpty ? cleanHref : "\(baseDir)/\(cleanHref)"
            guard let data = zip.read(fullPath),
                  let html = String(data: data, encoding: .utf8)
                    ?? String(data: data, encoding: .utf16) else { continue }

            let plain = htmlToPlainText(html)
            guard !plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }

            let title = firstMatch(in: html, pattern: #"<title[^>]*>([^<]*)</title>"#)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let title = title, !title.isEmpty {
                chapters.append(title)
            } else if let h = firstMatch(in: html, pattern: #"<h[1-3][^>]*>([^<]+)</h[1-3]>"#) {
                chapters.append(h.trimmingCharacters(in: .whitespacesAndNewlines))
            } else {
                chapters.append("第 \(chapters.count + 1) 节")
            }
            allText += plain + "\n\n"
        }

        guard !allText.isEmpty else { throw BookParseError.empty }
        return ParsedBook(title: bookTitle, text: allText, format: "epub", chapterTitles: chapters)
    }

    private static func htmlToPlainText(_ html: String) -> String {
        var s = html
        s = s.replacingOccurrences(of: #"<script[\s\S]*?</script>"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"<style[\s\S]*?</style>"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"</(p|div|h[1-6]|li|br|tr)[^>]*>"#, with: "\n", options: .regularExpression)
        s = s.replacingOccurrences(of: #"<br\s*/?>"#, with: "\n", options: .regularExpression)
        s = s.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "&nbsp;", with: " ")
        s = s.replacingOccurrences(of: "&amp;", with: "&")
        s = s.replacingOccurrences(of: "&lt;", with: "<")
        s = s.replacingOccurrences(of: "&gt;", with: ">")
        s = s.replacingOccurrences(of: "&quot;", with: "\"")
        s = s.replacingOccurrences(of: "&#39;", with: "'")
        return normalize(s)
    }

    // MARK: - PDF

    private static func parsePDF(url: URL, fallbackTitle: String) throws -> ParsedBook {
        guard let doc = PDFDocument(url: url) else { throw BookParseError.unreadable }
        var chapters: [String] = []
        var allText = ""
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i), let s = page.string else { continue }
            let trimmed = normalize(s).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            chapters.append("第 \(i + 1) 页")
            allText += trimmed + "\n\n"
        }
        guard !allText.isEmpty else { throw BookParseError.empty }
        let title = doc.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String ?? fallbackTitle
        return ParsedBook(title: title, text: allText, format: "pdf", chapterTitles: chapters)
    }

    // MARK: - helpers

    private static func firstMatch(in s: String, pattern: String) -> String? {
        guard let r = try? NSRegularExpression(pattern: pattern,
                                               options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return nil }
        let ns = s as NSString
        guard let m = r.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges >= 2 else { return nil }
        return ns.substring(with: m.range(at: 1))
    }
}
