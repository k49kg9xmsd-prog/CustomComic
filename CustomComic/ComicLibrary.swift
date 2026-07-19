import Foundation
import Combine
import UniformTypeIdentifiers
import ZIPFoundation

@MainActor
final class ComicLibrary: ObservableObject {
    @Published private(set) var books: [ComicBook] = []
    @Published private(set) var categories: [String] = ["未分類"]

    private let fileManager = FileManager.default
    private let metadataURL: URL
    private let categoriesURL: URL
    private let booksRoot: URL
    private var progressSaveTask: Task<Void, Never>?

    init() {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        booksRoot = documents.appendingPathComponent("Books", isDirectory: true)
        metadataURL = documents.appendingPathComponent("books.json")
        categoriesURL = documents.appendingPathComponent("categories.json")
        try? fileManager.createDirectory(at: booksRoot, withIntermediateDirectories: true)
        load()
    }

    var visibleBooks: [ComicBook] {
        books.filter { !$0.isHidden }
    }

    var hiddenBooks: [ComicBook] {
        books.filter(\.isHidden)
    }

    var recentlyReadBooks: [ComicBook] {
        visibleBooks
            .filter { $0.lastReadAt != nil }
            .sorted { ($0.lastReadAt ?? .distantPast) > ($1.lastReadAt ?? .distantPast) }
    }

    func books(in category: String) -> [ComicBook] {
        visibleBooks.filter { $0.category == category }
    }

    func book(id: UUID) -> ComicBook? {
        books.first { $0.id == id }
    }

    func episode(bookID: UUID, episodeID: UUID) -> ComicEpisode? {
        book(id: bookID)?.episodes.first { $0.id == episodeID }
    }

    func coverURL(for book: ComicBook) -> URL? {
        guard let episode = book.coverEpisode else { return nil }
        return coverURL(for: episode)
    }

    func coverURL(for episode: ComicEpisode) -> URL {
        booksRoot
            .appendingPathComponent(episode.folderName, isDirectory: true)
            .appendingPathComponent(episode.coverFileName)
    }

    func pageURLs(for episode: ComicEpisode) -> [URL] {
        let root = booksRoot.appendingPathComponent(episode.folderName, isDirectory: true)
        return episode.pageFileNames.map { root.appendingPathComponent($0) }
    }

    func exportZIP(for book: ComicBook) throws -> URL {
        let safeName = book.title.replacingOccurrences(of: "/", with: "-")
        let output = fileManager.temporaryDirectory.appendingPathComponent("\(safeName).zip")
        try? fileManager.removeItem(at: output)
        guard let archive = Archive(url: output, accessMode: .create) else {
            throw CocoaError(.fileWriteUnknown)
        }
        var used = Set<String>()
        for (episodeIndex, episode) in book.episodes.enumerated() {
            let pages = pageURLs(for: episode)
            for (pageIndex, url) in pages.enumerated() {
                let ext = url.pathExtension.isEmpty ? "jpg" : url.pathExtension
                var name = String(format: "%03d.%@", pageIndex + 1, ext)
                if book.episodes.count > 1 {
                    name = String(format: "%02d_%03d.%@", episodeIndex + 1, pageIndex + 1, ext)
                }
                while used.contains(name) { name = UUID().uuidString + "." + ext }
                used.insert(name)
                try archive.addEntry(with: name, fileURL: url, compressionMethod: .deflate)
            }
        }
        return output
    }

    @discardableResult
    func addCategory(_ rawName: String) -> String {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return "未分類" }

        if !categories.contains(name) {
            categories.append(name)
            categories.sort {
                if $0 == "未分類" { return true }
                if $1 == "未分類" { return false }
                return $0.localizedStandardCompare($1) == .orderedAscending
            }
            saveCategories()
        }
        return name
    }

    func createSeries(
        title: String,
        category: String,
        zipURLs: [URL],
        episodeTitles: [String],
        coverSource: URL?
    ) throws {
        guard !zipURLs.isEmpty else { return }

        var episodes: [ComicEpisode] = []
        do {
            for (index, zipURL) in zipURLs.enumerated() {
                let episodeTitle = episodeTitles.indices.contains(index)
                    ? episodeTitles[index]
                    : guessedEpisodeTitle(from: zipURL, index: index)
                let episode = try importEpisode(
                    zipURL: zipURL,
                    title: episodeTitle,
                    coverSource: index == 0 ? coverSource : nil
                )
                episodes.append(episode)
            }

            episodes.sort {
                $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }

            let cleanedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            let book = ComicBook(
                title: cleanedTitle.isEmpty
                    ? guessedSeriesTitle(from: zipURLs.first!)
                    : cleanedTitle,
                category: addCategory(category),
                episodes: episodes
            )
            books.insert(book, at: 0)
            saveBooks()
        } catch {
            for episode in episodes {
                try? fileManager.removeItem(
                    at: booksRoot.appendingPathComponent(episode.folderName, isDirectory: true)
                )
            }
            throw error
        }
    }

    func addEpisodes(
        to bookID: UUID,
        zipURLs: [URL],
        episodeTitles: [String]
    ) throws {
        guard let bookIndex = books.firstIndex(where: { $0.id == bookID }) else { return }

        var imported: [ComicEpisode] = []
        do {
            for (index, zipURL) in zipURLs.enumerated() {
                let title = episodeTitles.indices.contains(index)
                    ? episodeTitles[index]
                    : guessedEpisodeTitle(from: zipURL, index: books[bookIndex].episodes.count + index)
                imported.append(
                    try importEpisode(zipURL: zipURL, title: title, coverSource: nil)
                )
            }

            books[bookIndex].episodes.append(contentsOf: imported)
            books[bookIndex].episodes.sort {
                $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
            saveBooks()
        } catch {
            for episode in imported {
                try? fileManager.removeItem(
                    at: booksRoot.appendingPathComponent(episode.folderName, isDirectory: true)
                )
            }
            throw error
        }
    }

    private func importEpisode(
        zipURL: URL,
        title: String,
        coverSource: URL?
    ) throws -> ComicEpisode {
        let tempRoot = fileManager.temporaryDirectory
            .appendingPathComponent("CustomComicImport-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: tempRoot) }

        try fileManager.unzipItem(at: zipURL, to: tempRoot)

        guard let enumerator = fileManager.enumerator(
            at: tempRoot,
            includingPropertiesForKeys: [.isRegularFileKey, .contentTypeKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw NSError(
                domain: "CustomComic",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "無法讀取 ZIP 內容"]
            )
        }

        let images: [URL] = enumerator.compactMap { item in
            guard let url = item as? URL,
                  let values = try? url.resourceValues(
                    forKeys: [.isRegularFileKey, .contentTypeKey]
                  ),
                  values.isRegularFile == true,
                  values.contentType?.conforms(to: .image) == true
            else { return nil }
            return url
        }
        .sorted {
            $0.path.localizedStandardCompare($1.path) == .orderedAscending
        }

        guard !images.isEmpty else {
            throw NSError(
                domain: "CustomComic",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "\(zipURL.lastPathComponent) 裡沒有圖片"]
            )
        }

        let folderName = UUID().uuidString
        let destination = booksRoot.appendingPathComponent(folderName, isDirectory: true)
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)

        do {
            var copiedNames: [String] = []
            for (index, source) in images.enumerated() {
                let ext = source.pathExtension.isEmpty ? "jpg" : source.pathExtension.lowercased()
                let name = String(format: "%05d.%@", index + 1, ext)
                try fileManager.copyItem(
                    at: source,
                    to: destination.appendingPathComponent(name)
                )
                copiedNames.append(name)
            }

            let coverName: String
            if let coverSource {
                let ext = coverSource.pathExtension.isEmpty
                    ? "jpg"
                    : coverSource.pathExtension.lowercased()
                coverName = "cover.\(ext)"
                try fileManager.copyItem(
                    at: coverSource,
                    to: destination.appendingPathComponent(coverName)
                )
            } else {
                coverName = copiedNames[0]
            }

            return ComicEpisode(
                title: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? zipURL.deletingPathExtension().lastPathComponent
                    : title,
                folderName: folderName,
                coverFileName: coverName,
                pageFileNames: copiedNames
            )
        } catch {
            try? fileManager.removeItem(at: destination)
            throw error
        }
    }

    func guessedEpisodeTitle(from url: URL, index: Int) -> String {
        let raw = url.deletingPathExtension().lastPathComponent
        if let range = raw.range(
            of: #"(?:第\s*)?(\d+(?:\.\d+)?)\s*(?:集|卷|話|章|v|vol)?$"#,
            options: [.regularExpression, .caseInsensitive]
        ) {
            let match = String(raw[range])
            let number = match.filter { $0.isNumber || $0 == "." }
            if !number.isEmpty {
                return "第 \(number) 集"
            }
        }
        return "第 \(index + 1) 集"
    }

    func guessedSeriesTitle(from url: URL) -> String {
        let raw = url.deletingPathExtension().lastPathComponent
        return raw
            .replacingOccurrences(
                of: #"(?:第\s*)?\d+(?:\.\d+)?\s*(?:集|卷|話|章|v|vol)?$"#,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
            .trimmingCharacters(in: CharacterSet(charactersIn: " _-"))
    }

    func setHidden(_ hidden: Bool, for book: ComicBook) {
        guard let index = books.firstIndex(where: { $0.id == book.id }) else { return }
        books[index].isHidden = hidden
        saveBooks()
    }

    func toggleFavorite(_ book: ComicBook) {
        guard let index = books.firstIndex(where: { $0.id == book.id }) else { return }
        books[index].isFavorite.toggle()
        saveBooks()
    }

    func move(_ book: ComicBook, to category: String) {
        guard let index = books.firstIndex(where: { $0.id == book.id }) else { return }
        books[index].category = addCategory(category)
        saveBooks()
    }

    func delete(_ book: ComicBook) {
        for episode in book.episodes {
            try? fileManager.removeItem(
                at: booksRoot.appendingPathComponent(episode.folderName, isDirectory: true)
            )
        }
        books.removeAll { $0.id == book.id }
        saveBooks()
    }

    func batchDelete(ids: Set<UUID>) {
        books.filter { ids.contains($0.id) }.forEach { book in
            book.episodes.forEach { episode in
                try? fileManager.removeItem(at: booksRoot.appendingPathComponent(episode.folderName, isDirectory: true))
            }
        }
        books.removeAll { ids.contains($0.id) }
        saveBooks()
    }

    func batchSetHidden(ids: Set<UUID>, hidden: Bool) {
        for index in books.indices where ids.contains(books[index].id) { books[index].isHidden = hidden }
        saveBooks()
    }

    func batchSetCategory(ids: Set<UUID>, category: String) {
        let clean = addCategory(category)
        for index in books.indices where ids.contains(books[index].id) { books[index].category = clean }
        saveBooks()
    }

    func deleteEpisode(bookID: UUID, episodeID: UUID) {
        guard let bookIndex = books.firstIndex(where: { $0.id == bookID }),
              let episodeIndex = books[bookIndex].episodes.firstIndex(where: { $0.id == episodeID })
        else { return }

        let episode = books[bookIndex].episodes[episodeIndex]
        try? fileManager.removeItem(
            at: booksRoot.appendingPathComponent(episode.folderName, isDirectory: true)
        )
        books[bookIndex].episodes.remove(at: episodeIndex)

        if books[bookIndex].episodes.isEmpty {
            books.remove(at: bookIndex)
        }
        saveBooks()
    }

    func updateLastPage(bookID: UUID, episodeID: UUID, page: Int) {
        guard let bookIndex = books.firstIndex(where: { $0.id == bookID }),
              let episodeIndex = books[bookIndex].episodes.firstIndex(where: { $0.id == episodeID })
        else { return }

        guard books[bookIndex].episodes[episodeIndex].lastPage != page else { return }
        books[bookIndex].episodes[episodeIndex].lastPage = page
        books[bookIndex].lastReadAt = Date()

        // 閱讀時快速捲動會連續改頁；延遲合併寫入，避免每頁都同步寫 JSON 卡住 UI。
        progressSaveTask?.cancel()
        progressSaveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 650_000_000)
            guard !Task.isCancelled else { return }
            self?.saveBooks()
        }
    }

    private func load() {
        if let data = try? Data(contentsOf: metadataURL),
           let decoded = try? JSONDecoder().decode([ComicBook].self, from: data) {
            books = decoded.sorted { $0.createdAt > $1.createdAt }
        }

        if let data = try? Data(contentsOf: categoriesURL),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            categories = decoded
        }

        let usedCategories = Set(books.map(\.category))
        for category in usedCategories where !categories.contains(category) {
            categories.append(category)
        }
        if !categories.contains("未分類") {
            categories.insert("未分類", at: 0)
        }
        saveCategories()
        saveBooks()
    }

    private func saveBooks() {
        guard let data = try? JSONEncoder().encode(books) else { return }
        try? data.write(to: metadataURL, options: .atomic)
    }

    private func saveCategories() {
        guard let data = try? JSONEncoder().encode(categories) else { return }
        try? data.write(to: categoriesURL, options: .atomic)
    }
}
