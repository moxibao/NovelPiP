import Foundation
import SwiftUI

@MainActor
final class ReaderModel: ObservableObject {
    @Published var books: [Book] = []
    @Published var selectedBookID: UUID?
    @Published var pageIndex: Int = 0
    @Published var pages: [String] = []
    @Published var isPiPActive = false

    private let storageKey = "NovelPiP.books.v1"
    private let progressKey = "NovelPiP.progress.v1"

    var selectedBook: Book? { books.first { $0.id == selectedBookID } }
    var currentPage: String {
        guard pages.indices.contains(pageIndex) else { return "请导入一本 TXT 小说" }
        return pages[pageIndex]
    }

    init() { loadBooks() }

    func importText(data: Data, filename: String) {
        let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .utf16)
            ?? String(decoding: data, as: UTF8.self)
        let title = URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent
        let book = Book(title: title.isEmpty ? "未命名小说" : title, text: text)
        books.insert(book, at: 0)
        saveBooks()
        select(book)
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

    private func paginate(_ source: String) -> [String] {
        // Conservative character-based pagination. The PiP renderer uses a fixed
        // 720x405 canvas; page length can be tuned after device testing.
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
        guard let id = selectedBookID, let index = pages.isEmpty ? nil : Optional(pageIndex),
              let bookIndex = books.firstIndex(where: { $0.id == id }) else { return }
        books[bookIndex].pageIndex = index
        saveBooks()
    }
}
