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

    func videoURL(for item: VideoItem) -> URL { root.appendingPathComponent(item.fileName) }
    func coverURL(for item: VideoItem) -> URL { root.appendingPathComponent(item.coverFileName) }

    func importFiles(_ urls: [URL]) async throws {
        for url in urls { try await importFile(url, sourceURLString: nil, preferredTitle: nil, coverData: nil) }
    }

    func importPhotoData(_ data: Data, suggestedExtension: String = "mov") async throws {
        let temp = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(suggestedExtension)
        try data.write(to: temp, options: .atomic)
        defer { try? fm.removeItem(at: temp) }
        try await importFile(temp, sourceURLString: nil, preferredTitle: nil, coverData: nil)
    }

    func downloadDirectVideo(from url: URL, title: String?, coverData: Data?) async throws {
        let (temporaryURL, response) = try await URLSession.shared.download(from: url)
        let suggested = response.suggestedFilename ?? url.lastPathComponent
        let localTemp = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString + "-" + suggested)
        try? fm.removeItem(at: localTemp)
        try fm.moveItem(at: temporaryURL, to: localTemp)
        defer { try? fm.removeItem(at: localTemp) }
        try await importFile(localTemp, sourceURLString: url.absoluteString, preferredTitle: title, coverData: coverData)
    }

    func delete(_ item: VideoItem) {
        try? fm.removeItem(at: videoURL(for: item))
        try? fm.removeItem(at: coverURL(for: item))
        videos.removeAll { $0.id == item.id }
        save()
    }

    private func importFile(_ source: URL, sourceURLString: String?, preferredTitle: String?, coverData: Data?) async throws {
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
            videos.insert(VideoItem(title: title, fileName: fileName, coverFileName: coverName, sourceURLString: sourceURLString), at: 0)
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
