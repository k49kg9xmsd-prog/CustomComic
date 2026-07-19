import Foundation
import UIKit
import ZIPFoundation

struct IPAInspectionResult {
    var name: String
    var bundleIdentifier: String
    var version: String
    var build: String
    var iconData: Data?
}

enum IPAInspector {
    static func inspect(url: URL) throws -> IPAInspectionResult {
        guard let archive = Archive(url: url, accessMode: .read) else {
            throw IPAImportError.invalidArchive
        }

        guard let plistEntry = archive.first(where: {
            $0.path.hasPrefix("Payload/") &&
            $0.path.contains(".app/") &&
            $0.path.hasSuffix("Info.plist") &&
            $0.path.split(separator: "/").count == 3
        }) else {
            throw IPAImportError.infoPlistNotFound
        }

        var plistData = Data()
        _ = try archive.extract(plistEntry) { plistData.append($0) }
        guard let object = try PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) as? [String: Any] else {
            throw IPAImportError.unreadableInfoPlist
        }

        let name = (object["CFBundleDisplayName"] as? String)
            ?? (object["CFBundleName"] as? String)
            ?? "未命名 App"
        let bundleID = object["CFBundleIdentifier"] as? String ?? "未知"
        let version = object["CFBundleShortVersionString"] as? String ?? "未知"
        let build = object["CFBundleVersion"] as? String ?? "未知"
        let appRoot = String(plistEntry.path.dropLast("Info.plist".count))
        let iconNames = candidateIconNames(from: object)
        let iconEntry = findIconEntry(in: archive, appRoot: appRoot, candidates: iconNames)
        var iconData: Data?
        if let iconEntry {
            var data = Data()
            _ = try? archive.extract(iconEntry) { data.append($0) }
            iconData = data.isEmpty ? nil : data
        }

        return IPAInspectionResult(name: name, bundleIdentifier: bundleID, version: version, build: build, iconData: iconData)
    }

    private static func candidateIconNames(from plist: [String: Any]) -> [String] {
        var names: [String] = []
        func collect(_ dictionary: [String: Any]?) {
            guard let dictionary else { return }
            if let primary = dictionary["CFBundlePrimaryIcon"] as? [String: Any],
               let files = primary["CFBundleIconFiles"] as? [String] {
                names.append(contentsOf: files)
            }
        }
        collect(plist["CFBundleIcons"] as? [String: Any])
        collect(plist["CFBundleIcons~ipad"] as? [String: Any])
        if let files = plist["CFBundleIconFiles"] as? [String] { names.append(contentsOf: files) }
        return Array(Array(Set(names)).reversed())
    }

    private static func findIconEntry(in archive: Archive, appRoot: String, candidates: [String]) -> Entry? {
        for candidate in candidates {
            let base = candidate.replacingOccurrences(of: ".png", with: "")
            if let entry = archive.first(where: {
                $0.path.hasPrefix(appRoot) &&
                $0.path.lowercased().hasSuffix(".png") &&
                URL(fileURLWithPath: $0.path).lastPathComponent.lowercased().hasPrefix(base.lowercased())
            }) { return entry }
        }
        return archive.first(where: {
            $0.path.hasPrefix(appRoot) &&
            $0.path.lowercased().hasSuffix(".png") &&
            $0.path.lowercased().contains("appicon")
        })
    }
}
