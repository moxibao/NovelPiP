import Foundation

struct Chapter: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var startPage: Int
}

struct Book: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var text: String
    var pageIndex: Int = 0
    var chapters: [Chapter] = []
    var sourceFormat: String = "txt"
}
