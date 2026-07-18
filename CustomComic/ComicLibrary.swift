import Foundation
import Combine
import UniformTypeIdentifiers
import ZIPFoundation

@MainActor
final class ComicLibrary: ObservableObject {
    @Published private(set) var books: [ComicBook] = []

    private let fileManager = FileManager.default
    private let metadataURL: URL
    private let booksRoot: URL

    init() {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        booksRoot = documents.appendingPathComponent("Books", isDirectory: true)
        metadataURL = documents.appendingPathComponent("books.json")
        try? fileManager.createDirectory(at: booksRoot, withIntermediateDirectories: true)
        load()
    }

    func coverURL(for book: ComicBook) -> URL {
        booksRoot.appendingPathComponent(book.folderName, isDirectory: true)
            .appendingPathComponent(book.coverFileName)
    }

    func pageURLs(for book: ComicBook) -> [URL] {
        let root = booksRoot.appendingPathComponent(book.folderName, isDirectory: true)
        return book.pageFileNames.map { root.appendingPathComponent($0) }
    }

    func addBookFromZip(title: String, zipURL: URL, coverSource: URL?) throws {
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
                  let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .contentTypeKey]),
                  values.isRegularFile == true,
                  values.contentType?.conforms(to: .image) == true else {
                return nil
            }
            return url
        }
        .sorted {
            $0.path.localizedStandardCompare($1.path) == .orderedAscending
        }

        try addBook(title: title, sourceFiles: images, coverSource: coverSource)
    }

    private func addBook(title: String, sourceFiles: [URL], coverSource: URL?) throws {
        guard !sourceFiles.isEmpty else {
            throw NSError(
                domain: "CustomComic",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "ZIP 裡沒有找到可用圖片"]
            )
        }

        let id = UUID()
        let folderName = id.uuidString
        let destination = booksRoot.appendingPathComponent(folderName, isDirectory: true)
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)

        do {
            var copiedNames: [String] = []

            for (index, source) in sourceFiles.enumerated() {
                let ext = source.pathExtension.isEmpty ? "jpg" : source.pathExtension.lowercased()
                let name = String(format: "%05d.%@", index + 1, ext)
                let target = destination.appendingPathComponent(name)
                try fileManager.copyItem(at: source, to: target)
                copiedNames.append(name)
            }

            let coverName: String
            if let coverSource {
                let ext = coverSource.pathExtension.isEmpty ? "jpg" : coverSource.pathExtension.lowercased()
                coverName = "cover.\(ext)"
                try fileManager.copyItem(
                    at: coverSource,
                    to: destination.appendingPathComponent(coverName)
                )
            } else {
                // 沒選封面時，每本漫畫隨機挑一張。
                coverName = copiedNames.randomElement() ?? copiedNames[0]
            }

            let cleanedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            let book = ComicBook(
                id: id,
                title: cleanedTitle.isEmpty ? zipFallbackTitle(from: sourceFiles) : cleanedTitle,
                folderName: folderName,
                coverFileName: coverName,
                pageFileNames: copiedNames,
                lastPage: 0,
                createdAt: Date()
            )

            books.insert(book, at: 0)
            save()
        } catch {
            try? fileManager.removeItem(at: destination)
            throw error
        }
    }

    private func zipFallbackTitle(from files: [URL]) -> String {
        files.first?.deletingLastPathComponent().lastPathComponent ?? "未命名作品"
    }

    func delete(_ book: ComicBook) {
        try? fileManager.removeItem(
            at: booksRoot.appendingPathComponent(book.folderName, isDirectory: true)
        )
        books.removeAll { $0.id == book.id }
        save()
    }

    func updateLastPage(bookID: UUID, page: Int) {
        guard let index = books.firstIndex(where: { $0.id == bookID }) else { return }
        books[index].lastPage = page
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: metadataURL),
              let decoded = try? JSONDecoder().decode([ComicBook].self, from: data) else {
            return
        }
        books = decoded.sorted { $0.createdAt > $1.createdAt }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(books) else { return }
        try? data.write(to: metadataURL, options: .atomic)
    }
}
