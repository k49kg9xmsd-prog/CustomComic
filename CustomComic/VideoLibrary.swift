import Foundation
import AVFoundation
import UIKit

@MainActor
final class VideoLibrary: ObservableObject {
    @Published private(set) var videos: [VideoItem] = []

    private let fm = FileManager.default
    private let root: URL
    private let metadataURL: URL

    init() {
        let documents = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        root = documents.appendingPathComponent("Videos", isDirectory: true)
        metadataURL = documents.appendingPathComponent("videos.json")
        try? fm.createDirectory(at: root, withIntermediateDirectories: true)
        load()
    }

    var visibleVideos: [VideoItem] { videos.filter { !$0.isHidden } }
    var hiddenVideos: [VideoItem] { videos.filter(\.isHidden) }
    var categories: [String] {
        Array(Set(visibleVideos.map { $0.category.isEmpty ? "未分類" : $0.category })).sorted()
    }
    var recentlyWatchedVideos: [VideoItem] {
        visibleVideos.filter { $0.lastWatchedAt != nil }.sorted {
            ($0.lastWatchedAt ?? .distantPast) > ($1.lastWatchedAt ?? .distantPast)
        }
    }

    func videoURL(for item: VideoItem) -> URL { root.appendingPathComponent(item.fileName) }
    func coverURL(for item: VideoItem) -> URL { root.appendingPathComponent(item.coverFileName) }

    func importFiles(_ urls: [URL]) async throws {
        for url in urls { try await importFile(url, sourceURLString: nil, preferredTitle: nil, category: "未分類", coverData: nil) }
    }

    func importSeries(
        urls: [URL],
        seriesTitle: String,
        episodeTitles: [String],
        category: String,
        coverData: Data?
    ) async throws {
        let cleanSeriesTitle = seriesTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanCategory = category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "未分類" : category
        for (index, url) in urls.enumerated() {
            let episode = index < episodeTitles.count ? episodeTitles[index].trimmingCharacters(in: .whitespacesAndNewlines) : ""
            let fallback = url.deletingPathExtension().lastPathComponent
            let displayTitle: String
            if urls.count == 1 {
                displayTitle = cleanSeriesTitle.isEmpty ? (episode.isEmpty ? fallback : episode) : cleanSeriesTitle
            } else {
                let part = episode.isEmpty ? "第 \(index + 1) 集" : episode
                displayTitle = cleanSeriesTitle.isEmpty ? part : "\(cleanSeriesTitle) · \(part)"
            }
            try await importFile(
                url,
                sourceURLString: nil,
                preferredTitle: displayTitle,
                category: cleanCategory,
                coverData: coverData
            )
        }
    }

    func importPhotoData(_ data: Data, suggestedExtension: String = "mov") async throws {
        let temp = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(suggestedExtension)
        try data.write(to: temp, options: .atomic)
        defer { try? fm.removeItem(at: temp) }
        try await importFile(temp, sourceURLString: nil, preferredTitle: nil, category: "未分類", coverData: nil)
    }

    func downloadDirectVideo(from url: URL, title: String?, coverData: Data?) async throws {
        let (temporaryURL, response) = try await URLSession.shared.download(from: url)
        let suggested = response.suggestedFilename ?? url.lastPathComponent
        let localTemp = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString + "-" + suggested)
        try? fm.removeItem(at: localTemp)
        try fm.moveItem(at: temporaryURL, to: localTemp)
        defer { try? fm.removeItem(at: localTemp) }
        try await importFile(localTemp, sourceURLString: url.absoluteString, preferredTitle: title, category: "未分類", coverData: coverData)
    }

    func toggleFavorite(_ item: VideoItem) {
        update(item) { $0.isFavorite.toggle() }
    }

    func toggleHidden(_ item: VideoItem) {
        update(item) { $0.isHidden.toggle() }
    }

    func markWatched(_ item: VideoItem) {
        update(item) { $0.lastWatchedAt = Date() }
    }

    func updateProgress(_ item: VideoItem, position: Double, duration: Double) {
        update(item) { value in
            value.lastPosition = max(0, position)
            value.duration = max(0, duration)
            value.lastWatchedAt = Date()
        }
    }

    func resetProgress(_ item: VideoItem) {
        update(item) { value in
            value.lastPosition = 0
            value.lastWatchedAt = nil
        }
    }

    func batchDelete(ids: Set<UUID>) {
        videos.filter { ids.contains($0.id) }.forEach { item in
            try? fm.removeItem(at: videoURL(for: item))
            try? fm.removeItem(at: coverURL(for: item))
        }
        videos.removeAll { ids.contains($0.id) }
        save()
    }

    func batchSetHidden(ids: Set<UUID>, hidden: Bool) {
        for index in videos.indices where ids.contains(videos[index].id) { videos[index].isHidden = hidden }
        save()
    }

    func batchSetCategory(ids: Set<UUID>, category: String) {
        let clean = category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "未分類" : category
        for index in videos.indices where ids.contains(videos[index].id) { videos[index].category = clean }
        save()
    }

    func updateMetadata(_ item: VideoItem, title: String, category: String) {
        update(item) {
            $0.title = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? $0.title : title
            let trimmed = category.trimmingCharacters(in: .whitespacesAndNewlines)
            $0.category = trimmed.isEmpty ? "未分類" : trimmed
        }
    }

    private func update(_ item: VideoItem, change: (inout VideoItem) -> Void) {
        guard let index = videos.firstIndex(where: { $0.id == item.id }) else { return }
        change(&videos[index])
        save()
    }

    func delete(_ item: VideoItem) {
        try? fm.removeItem(at: videoURL(for: item))
        try? fm.removeItem(at: coverURL(for: item))
        videos.removeAll { $0.id == item.id }
        save()
    }

    private func importFile(_ source: URL, sourceURLString: String?, preferredTitle: String?, category: String, coverData: Data?) async throws {
        let ext = source.pathExtension.isEmpty ? "mov" : source.pathExtension.lowercased()
        let base = UUID().uuidString
        let fileName = base + "." + ext
        let coverName = base + ".jpg"
        let destination = root.appendingPathComponent(fileName)
        try fm.copyItem(at: source, to: destination)

        do {
            let generatedCover: Data
            if let coverData { generatedCover = coverData }
            else { generatedCover = try await Self.firstFrameJPEG(from: destination) }
            try generatedCover.write(to: root.appendingPathComponent(coverName), options: .atomic)

            let guessed = source.deletingPathExtension().lastPathComponent
            let title = (preferredTitle?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? preferredTitle! : guessed)
            videos.insert(VideoItem(title: title, category: category, fileName: fileName, coverFileName: coverName, sourceURLString: sourceURLString), at: 0)
            save()
        } catch {
            try? fm.removeItem(at: destination)
            throw error
        }
    }

    nonisolated private static func firstFrameJPEG(from url: URL) async throws -> Data {
        try await Task.detached(priority: .userInitiated) {
            let asset = AVURLAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 900, height: 900)
            let image = try generator.copyCGImage(at: CMTime(seconds: 0.1, preferredTimescale: 600), actualTime: nil)
            guard let data = UIImage(cgImage: image).jpegData(compressionQuality: 0.86) else {
                throw NSError(domain: "CustomComic.Video", code: 2, userInfo: [NSLocalizedDescriptionKey: "無法產生影片封面"])
            }
            return data
        }.value
    }

    private func load() {
        guard let data = try? Data(contentsOf: metadataURL), let decoded = try? JSONDecoder().decode([VideoItem].self, from: data) else { return }
        videos = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(videos) else { return }
        try? data.write(to: metadataURL, options: .atomic)
    }
}
