import Foundation

struct ComicEpisode: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var folderName: String
    var coverFileName: String
    var pageFileNames: [String]
    var lastPage: Int
    var createdAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        folderName: String,
        coverFileName: String,
        pageFileNames: [String],
        lastPage: Int = 0,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.folderName = folderName
        self.coverFileName = coverFileName
        self.pageFileNames = pageFileNames
        self.lastPage = lastPage
        self.createdAt = createdAt
    }
}

struct ComicBook: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var category: String
    var isHidden: Bool
    var isFavorite: Bool
    var createdAt: Date
    var lastReadAt: Date?
    var episodes: [ComicEpisode]

    init(
        id: UUID = UUID(),
        title: String,
        category: String = "未分類",
        isHidden: Bool = false,
        isFavorite: Bool = false,
        createdAt: Date = Date(),
        lastReadAt: Date? = nil,
        episodes: [ComicEpisode] = []
    ) {
        self.id = id
        self.title = title
        self.category = category
        self.isHidden = isHidden
        self.isFavorite = isFavorite
        self.createdAt = createdAt
        self.lastReadAt = lastReadAt
        self.episodes = episodes
    }

    var coverEpisode: ComicEpisode? {
        episodes.first
    }

    var progressText: String {
        guard let episode = episodes.first(where: { $0.lastPage > 0 }) ?? episodes.first else {
            return "尚未閱讀"
        }
        let total = max(episode.pageFileNames.count, 1)
        return "\(min(episode.lastPage + 1, total)) / \(total)"
    }

    enum CodingKeys: String, CodingKey {
        case id, title, category, isHidden, isFavorite, createdAt, lastReadAt, episodes

        // v7 舊資料
        case folderName, coverFileName, pageFileNames, lastPage
    }

    func encode(to encoder: Encoder) throws {
        var box = encoder.container(keyedBy: CodingKeys.self)
        try box.encode(id, forKey: .id)
        try box.encode(title, forKey: .title)
        try box.encode(category, forKey: .category)
        try box.encode(isHidden, forKey: .isHidden)
        try box.encode(isFavorite, forKey: .isFavorite)
        try box.encode(createdAt, forKey: .createdAt)
        try box.encodeIfPresent(lastReadAt, forKey: .lastReadAt)
        try box.encode(episodes, forKey: .episodes)
    }

    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        id = try box.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try box.decodeIfPresent(String.self, forKey: .title) ?? "未命名作品"
        category = try box.decodeIfPresent(String.self, forKey: .category) ?? "未分類"
        isHidden = try box.decodeIfPresent(Bool.self, forKey: .isHidden) ?? false
        isFavorite = try box.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        createdAt = try box.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        lastReadAt = try box.decodeIfPresent(Date.self, forKey: .lastReadAt)

        if let decodedEpisodes = try box.decodeIfPresent([ComicEpisode].self, forKey: .episodes) {
            episodes = decodedEpisodes
        } else if
            let folderName = try box.decodeIfPresent(String.self, forKey: .folderName),
            let coverFileName = try box.decodeIfPresent(String.self, forKey: .coverFileName),
            let pageFileNames = try box.decodeIfPresent([String].self, forKey: .pageFileNames)
        {
            let oldLastPage = try box.decodeIfPresent(Int.self, forKey: .lastPage) ?? 0
            episodes = [
                ComicEpisode(
                    title: "第 1 集",
                    folderName: folderName,
                    coverFileName: coverFileName,
                    pageFileNames: pageFileNames,
                    lastPage: oldLastPage,
                    createdAt: createdAt
                )
            ]
        } else {
            episodes = []
        }
    }
}

enum ReadingMode: String, CaseIterable, Identifiable {
    case vertical
    case paged

    var id: String { rawValue }

    var title: String {
        switch self {
        case .vertical: return "連續捲軸"
        case .paged: return "單頁翻頁"
        }
    }

    var subtitle: String {
        switch self {
        case .vertical: return "整集連續上下閱讀，縮放不會突然重設"
        case .paged: return "點左右翻頁，支援雙指縮放與拖動"
        }
    }
}

enum ResumeBehavior: String, CaseIterable, Identifiable {
    case ask
    case alwaysResume
    case alwaysStartOver

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ask: return "每次詢問"
        case .alwaysResume: return "直接繼續閱讀"
        case .alwaysStartOver: return "每次從頭開始"
        }
    }
}


struct SavedWebsite: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var urlString: String
}

enum LibraryTab: String, CaseIterable, Identifiable {
    case local
    case web

    var id: String { rawValue }

    var title: String {
        switch self {
        case .local: return "本地漫畫"
        case .web: return "網頁"
        }
    }
}

enum AppBackgroundStyle: String, CaseIterable, Identifiable {
    case solid
    case image
    case video

    var id: String { rawValue }

    var title: String {
        switch self {
        case .solid: return "純色"
        case .image: return "圖片"
        case .video: return "影片"
        }
    }
}

enum LibraryMode: String, CaseIterable, Identifiable {
    case comic
    case animation

    var id: String { rawValue }
    var title: String { self == .comic ? "漫畫" : "動畫" }
    var icon: String { self == .comic ? "books.vertical.fill" : "play.rectangle.fill" }
}

struct VideoItem: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var category: String
    var fileName: String
    var coverFileName: String
    var isHidden: Bool
    var isFavorite: Bool
    var createdAt: Date
    var lastWatchedAt: Date?
    var sourceURLString: String?

    init(
        id: UUID = UUID(),
        title: String,
        category: String = "未分類",
        fileName: String,
        coverFileName: String,
        isHidden: Bool = false,
        isFavorite: Bool = false,
        createdAt: Date = Date(),
        lastWatchedAt: Date? = nil,
        sourceURLString: String? = nil
    ) {
        self.id = id
        self.title = title
        self.category = category
        self.fileName = fileName
        self.coverFileName = coverFileName
        self.isHidden = isHidden
        self.isFavorite = isFavorite
        self.createdAt = createdAt
        self.lastWatchedAt = lastWatchedAt
        self.sourceURLString = sourceURLString
    }

    enum CodingKeys: String, CodingKey {
        case id, title, category, fileName, coverFileName, isHidden, isFavorite
        case createdAt, lastWatchedAt, sourceURLString
    }

    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        id = try box.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try box.decodeIfPresent(String.self, forKey: .title) ?? "未命名動畫"
        category = try box.decodeIfPresent(String.self, forKey: .category) ?? "未分類"
        fileName = try box.decode(String.self, forKey: .fileName)
        coverFileName = try box.decode(String.self, forKey: .coverFileName)
        isHidden = try box.decodeIfPresent(Bool.self, forKey: .isHidden) ?? false
        isFavorite = try box.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        createdAt = try box.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        lastWatchedAt = try box.decodeIfPresent(Date.self, forKey: .lastWatchedAt)
        sourceURLString = try box.decodeIfPresent(String.self, forKey: .sourceURLString)
    }
}
