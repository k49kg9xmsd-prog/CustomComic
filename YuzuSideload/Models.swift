import Foundation

struct IPAItem: Identifiable, Codable, Hashable {
    let id: UUID
    var displayName: String
    var bundleIdentifier: String
    var version: String
    var build: String
    var fileName: String
    var fileSize: Int64
    var importedAt: Date
    var iconFileName: String?

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }
}

enum IPAImportError: LocalizedError {
    case invalidArchive
    case appNotFound
    case infoPlistNotFound
    case unreadableInfoPlist
    case copyFailed

    var errorDescription: String? {
        switch self {
        case .invalidArchive: return "這不是有效的 IPA／ZIP 壓縮檔。"
        case .appNotFound: return "IPA 內找不到 Payload/*.app。"
        case .infoPlistNotFound: return "App 內找不到 Info.plist。"
        case .unreadableInfoPlist: return "無法讀取 App 資訊。"
        case .copyFailed: return "無法把 IPA 保存到本機。"
        }
    }
}
