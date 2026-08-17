import Foundation
import Combine
import UserNotifications

struct DownloadRecord: Identifiable, Codable, Equatable {
    enum Status: String, Codable {
        case waiting
        case downloading
        case finished
        case failed
        case cancelled
    }

    var id: UUID
    var title: String
    var sourceURL: String
    var localFileName: String?
    var progress: Double
    var status: Status
    var errorText: String?
}

@MainActor
final class DownloadManager: NSObject, ObservableObject {
    @Published private(set) var records: [DownloadRecord] = []

    private var session: URLSession!
    private let recordsURL: URL
    private let downloadsFolder: URL

    override init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        recordsURL = documents.appendingPathComponent("downloads.json")
        downloadsFolder = documents.appendingPathComponent("WebDownloads", isDirectory: true)

        super.init()

        try? FileManager.default.createDirectory(
            at: downloadsFolder,
            withIntermediateDirectories: true
        )

        let config = URLSessionConfiguration.background(
            withIdentifier: "com.customcomic.reader.background-downloads"
        )
        config.sessionSendsLaunchEvents = true
        config.isDiscretionary = false
        session = URLSession(
            configuration: config,
            delegate: self,
            delegateQueue: nil
        )
        load()
    }

    func start(
        url: URL,
        title: String? = nil,
        cookieHeader: String? = nil,
        referer: URL? = nil,
        userAgent: String? = nil
    ) {
        let id = UUID()
        let record = DownloadRecord(
            id: id,
            title: title ?? url.lastPathComponent,
            sourceURL: url.absoluteString,
            localFileName: nil,
            progress: 0,
            status: .waiting,
            errorText: nil
        )
        records.insert(record, at: 0)
        save()

        var request = URLRequest(url: url)
        request.setValue(
            userAgent ?? "Mozilla/5.0 CustomComic/1.0",
            forHTTPHeaderField: "User-Agent"
        )

        if let cookieHeader, !cookieHeader.isEmpty {
            request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        }

        if let referer {
            request.setValue(referer.absoluteString, forHTTPHeaderField: "Referer")
        }

        let task = session.downloadTask(with: request)
        task.taskDescription = id.uuidString
        task.resume()

        update(id: id) {
            $0.status = .downloading
        }
    }

    func cancel(_ record: DownloadRecord) {
        session.getAllTasks { tasks in
            tasks
                .filter { $0.taskDescription == record.id.uuidString }
                .forEach { $0.cancel() }
        }
        update(id: record.id) {
            $0.status = .cancelled
        }
    }

    private func update(id: UUID, _ change: (inout DownloadRecord) -> Void) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        change(&records[index])
        save()
    }

    private func load() {
        if let data = try? Data(contentsOf: recordsURL),
           let decoded = try? JSONDecoder().decode([DownloadRecord].self, from: data) {
            records = decoded
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? data.write(to: recordsURL, options: .atomic)
    }

    private func notifyFinished(title: String) {
        let content = UNMutableNotificationContent()
        content.title = "下載完成"
        content.body = title
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}

extension DownloadManager: URLSessionDownloadDelegate {
    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let raw = downloadTask.taskDescription,
              let id = UUID(uuidString: raw),
              totalBytesExpectedToWrite > 0
        else { return }

        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        Task { @MainActor in
            self.update(id: id) {
                $0.status = .downloading
                $0.progress = progress
            }
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let raw = downloadTask.taskDescription,
              let id = UUID(uuidString: raw)
        else { return }

        Task { @MainActor in
            guard let index = self.records.firstIndex(where: { $0.id == id }) else { return }
            let ext = downloadTask.originalRequest?.url?.pathExtension
            let filename = ext?.isEmpty == false
                ? "\(id.uuidString).\(ext!)"
                : "\(id.uuidString).download"
            let target = self.downloadsFolder.appendingPathComponent(filename)

            do {
                if FileManager.default.fileExists(atPath: target.path) {
                    try FileManager.default.removeItem(at: target)
                }
                try FileManager.default.moveItem(at: location, to: target)
                self.records[index].localFileName = filename
                self.records[index].progress = 1
                self.records[index].status = .finished
                self.records[index].errorText = nil
                self.save()
                self.notifyFinished(title: self.records[index].title)
            } catch {
                self.records[index].status = .failed
                self.records[index].errorText = error.localizedDescription
                self.save()
            }
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let error,
              let raw = task.taskDescription,
              let id = UUID(uuidString: raw)
        else { return }

        Task { @MainActor in
            self.update(id: id) {
                if (error as NSError).code == NSURLErrorCancelled {
                    $0.status = .cancelled
                } else {
                    $0.status = .failed
                    $0.errorText = error.localizedDescription
                }
            }
        }
    }
}
