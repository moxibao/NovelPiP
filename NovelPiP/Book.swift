import Foundation

struct Book: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var text: String
    var pageIndex: Int = 0
}
