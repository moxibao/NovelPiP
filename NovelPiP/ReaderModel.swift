import Foundation
import SwiftUI

@MainActor
final class ReaderModel: ObservableObject {
    @Published var books: [Book] = []
    @Published var selectedBookID: UUID?
    @Published var pageIndex: Int = 0
    @Published var pages: [String] = []
    @Published var isPiPActive = false
    @Published var importError: String?
    @Published var isImporting = false

    private let storageKey = "NovelPiP.books.v2"

    var selectedBook: Book? { books.first { $0.id == selectedBookID } }
    var currentPage: String {
        guard pages.indices.contains(pageIndex) else { return "请导入一本小说" }
        return pages[pageIndex]
    }

    var currentChapterTitle: String? {
        guard let book = selectedBook, !book.chapters.isEmpty else { return nil }
        var result: String?
        for c in book.chapters where c.startPage <= pageIndex { result = c.title }
        return result
    }

    init() { loadBooks() }

    func importFile(url: URL) {
        isImporting = true
        let access = url.startAccessingSecurityScopedResource()

        Task.detached(priority: .userInitiated) { [weak self] in
            defer {
                if access { url.stopAccessingSecurityScopedResource() }
            }

            do {
                let parsed = try BookParser.parse(url: url)
                let paged = await self?.paginate(parsed.text) ?? []
                let chapters = await self?.mapChapters(
                    titles: parsed.chapterTitles,
                    text: parsed.text,
                    pages: paged
                ) ?? []

                await MainActor.run {
                    guard let self else { return }
                    var book = Book(title: parsed.title, text: parsed.text, sourceFormat: parsed.format)
                    book.chapters = chapters
                    self.books.insert(book, at: 0)
                    self.saveBooks()
                    self.select(book)
                    self.isImporting = false
                }
            } catch {
                await MainActor.run {
                    self?.importError = error.localizedDescription
                    self?.isImporting = false
                }
            }
        }
    }

    func delete(_ book: Book) {
        books.removeAll { $0.id == book.id }
        if selectedBookID == book.id {
            selectedBookID = nil
            pages = []
            pageIndex = 0
            if let first = books.first { select(first) }
        }
        saveBooks()
    }

    func select(_ book: Book) {
        selectedBookID = book.id
        pages = paginate(book.text)
        pageIndex = min(book.pageIndex, max(0, pages.count - 1))
    }

    func nextPage() {
        guard !pages.isEmpty else { return }
        pageIndex = min(pageIndex + 1, pages.count - 1)
        saveProgress()
    }

    func previousPage() {
        guard !pages.isEmpty else { return }
        pageIndex = max(0, pageIndex - 1)
        saveProgress()
    }

    func goToPage(_ index: Int) {
        guard !pages.isEmpty else { return }
        pageIndex = min(max(0, index), pages.count - 1)
        saveProgress()
    }

    func goToChapter(_ chapter: Chapter) {
        goToPage(chapter.startPage)
    }

    private nonisolated func paginate(_ source: String) -> [String] {
        let normalized = source
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let chars = Array(normalized)
        let capacity = 330
        guard !chars.isEmpty else { return ["（这本书暂时没有正文）"] }
        var result: [String] = []
        var start = 0
        while start < chars.count {
            let end = min(start + capacity, chars.count)
            var slice = Array(chars[start..<end])
            if end < chars.count, let breakIndex = slice.lastIndex(where: { $0 == "\n" || $0 == "。" || $0 == "！" || $0 == "？" }) {
                let cut = breakIndex + 1
                if cut > capacity / 2 {
                    slice = Array(slice.prefix(cut))
                    start += cut
                } else {
                    start = end
                }
            } else {
                start = end
            }
            result.append(String(slice).trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return result.isEmpty ? [""] : result
    }

    private nonisolated func mapChapters(titles: [String], text: String, pages: [String]) -> [Chapter] {
        guard !titles.isEmpty, !pages.isEmpty else { return [] }
        var pageStartOffsets: [Int] = []
        var offset = 0
        for p in pages {
            pageStartOffsets.append(offset)
            offset += p.count
        }
        var chapters: [Chapter] = []
        var searchFrom = text.startIndex
        for t in titles {
            guard let r = text.range(of: t, range: searchFrom..<text.endIndex) else { continue }
            let charOffset = text.distance(from: text.startIndex, to: r.lowerBound)
            var page = 0
            for (i, off) in pageStartOffsets.enumerated() where off <= charOffset { page = i }
            chapters.append(Chapter(title: t, startPage: page))
            searchFrom = r.upperBound
        }
        return chapters
    }

    private func loadBooks() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([Book].self, from: data) else { return }
        books = decoded
        if let first = books.first { select(first) }
    }

    private func saveBooks() {
        if let data = try? JSONEncoder().encode(books) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func saveProgress() {
        guard let id = selectedBookID,
              let bookIndex = books.firstIndex(where: { $0.id == id }) else { return }
        books[bookIndex].pageIndex = pageIndex
        saveBooks()
    }
}
