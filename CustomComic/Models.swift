import Foundation

struct ComicBook: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var folderName: String
    var coverFileName: String
    var pageFileNames: [String]
    var lastPage: Int
    var createdAt: Date
}

enum ReadingMode: String, CaseIterable, Identifiable {
    case vertical
    case paged

    var id: String { rawValue }

    var title: String {
        self == .vertical ? "直向滑動" : "左右點擊翻頁"
    }

    var subtitle: String {
        self == .vertical ? "圖片一張接一張往下閱讀" : "點右邊下一頁，點左邊上一頁"
    }
}
