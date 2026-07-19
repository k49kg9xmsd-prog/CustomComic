import Foundation

@MainActor
final class IPALibrary: ObservableObject {
    @Published private(set) var items: [IPAItem] = []
    @Published var isImporting = false
    @Published var lastError: String?

    private let fm = FileManager.default
    private var rootURL: URL { fm.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("IPAStore", isDirectory: true) }
    private var metadataURL: URL { rootURL.appendingPathComponent("library.json") }

    init() {
        try? fm.createDirectory(at: rootURL, withIntermediateDirectories: true)
        load()
    }

    func fileURL(for item: IPAItem) -> URL { rootURL.appendingPathComponent(item.fileName) }
    func iconURL(for item: IPAItem) -> URL? { item.iconFileName.map { rootURL.appendingPathComponent($0) } }

    func importIPA(from sourceURL: URL) async {
        isImporting = true
        lastError = nil
        defer { isImporting = false }
        let access = sourceURL.startAccessingSecurityScopedResource()
        defer { if access { sourceURL.stopAccessingSecurityScopedResource() } }

        do {
            let temp = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".ipa")
            try? fm.removeItem(at: temp)
            try fm.copyItem(at: sourceURL, to: temp)
            let inspection = try await Task.detached(priority: .userInitiated) { try IPAInspector.inspect(url: temp) }.value
            let id = UUID()
            let storedName = id.uuidString + ".ipa"
            let destination = rootURL.appendingPathComponent(storedName)
            try fm.moveItem(at: temp, to: destination)
            let size = (try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
            var iconName: String?
            if let iconData = inspection.iconData {
                let name = id.uuidString + ".png"
                try? iconData.write(to: rootURL.appendingPathComponent(name), options: .atomic)
                iconName = name
            }
            let item = IPAItem(id: id, displayName: inspection.name, bundleIdentifier: inspection.bundleIdentifier, version: inspection.version, build: inspection.build, fileName: storedName, fileSize: size, importedAt: Date(), iconFileName: iconName)
            items.insert(item, at: 0)
            save()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func delete(_ item: IPAItem) {
        try? fm.removeItem(at: fileURL(for: item))
        if let icon = iconURL(for: item) { try? fm.removeItem(at: icon) }
        items.removeAll { $0.id == item.id }
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: metadataURL), let decoded = try? JSONDecoder().decode([IPAItem].self, from: data) else { return }
        items = decoded.filter { fm.fileExists(atPath: fileURL(for: $0).path) }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(items) { try? data.write(to: metadataURL, options: .atomic) }
    }
}
