import Foundation
import SwiftUI

struct OnlineVideoRule: Identifiable, Codable, Hashable {
    var id: String { name }
    let name: String
    let baseURL: String
    let searchURL: String
    let resultPattern: String
    let titleGroup: Int
    let detailURLGroup: Int
    let coverURLGroup: Int?
    let episodePattern: String
    let episodeTitleGroup: Int
    let episodeURLGroup: Int
    let videoPattern: String
    let videoURLGroup: Int
    var headers: [String: String]?

    func searchRequestURL(keyword: String) -> URL? {
        let encoded = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? keyword
        return absoluteURL(searchURL.replacingOccurrences(of: "@keyword", with: encoded))
    }

    func absoluteURL(_ value: String) -> URL? {
        let decoded = value
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "\\/", with: "/")
        if let url = URL(string: decoded), url.scheme != nil { return url }
        guard let base = URL(string: baseURL) else { return nil }
        return URL(string: decoded, relativeTo: base)?.absoluteURL
    }
}

struct OnlineAnimeResult: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let detailURL: URL
    let coverURL: URL?
    let rule: OnlineVideoRule
}

struct OnlineEpisode: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let pageURL: URL
    let rule: OnlineVideoRule
}

@MainActor
final class OnlineVideoRuleStore: ObservableObject {
    @Published private(set) var rules: [OnlineVideoRule] = []
    private let fileURL: URL

    init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = documents.appendingPathComponent("online-video-rules.json")
        load()
    }

    func importRules(from data: Data) throws {
        let decoder = JSONDecoder()
        let imported: [OnlineVideoRule]
        if let many = try? decoder.decode([OnlineVideoRule].self, from: data) {
            imported = many
        } else {
            imported = [try decoder.decode(OnlineVideoRule.self, from: data)]
        }
        var merged = Dictionary(uniqueKeysWithValues: rules.map { ($0.name, $0) })
        imported.forEach { merged[$0.name] = $0 }
        rules = merged.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        try save()
    }

    func remove(at offsets: IndexSet) {
        rules.remove(atOffsets: offsets)
        try? save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([OnlineVideoRule].self, from: data) else { return }
        rules = decoded
    }

    private func save() throws {
        let data = try JSONEncoder().encode(rules)
        try data.write(to: fileURL, options: .atomic)
    }
}

enum OnlineVideoRuleError: LocalizedError {
    case noRules
    case invalidResponse
    case noEpisodes
    case noPlayableURL

    var errorDescription: String? {
        switch self {
        case .noRules: return "尚未匯入任何來源規則。"
        case .invalidResponse: return "來源回傳的內容無法解析。"
        case .noEpisodes: return "規則沒有解析到任何集數。"
        case .noPlayableURL: return "沒有解析到可播放的影片網址。"
        }
    }
}

actor OnlineVideoRuleEngine {
    static let shared = OnlineVideoRuleEngine()

    func search(keyword: String, rules: [OnlineVideoRule]) async throws -> [OnlineAnimeResult] {
        guard !rules.isEmpty else { throw OnlineVideoRuleError.noRules }
        return try await withThrowingTaskGroup(of: [OnlineAnimeResult].self) { group in
            for rule in rules {
                group.addTask { try await self.search(keyword: keyword, rule: rule) }
            }
            var all: [OnlineAnimeResult] = []
            for try await values in group { all.append(contentsOf: values) }
            return all.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        }
    }

    func episodes(for result: OnlineAnimeResult) async throws -> [OnlineEpisode] {
        if ["m3u8", "mp4"].contains(result.detailURL.pathExtension.lowercased()) {
            return [OnlineEpisode(title: result.title, pageURL: result.detailURL, rule: result.rule)]
        }
        let html = try await fetchText(url: result.detailURL, rule: result.rule, referer: nil)
        let matches = captures(pattern: result.rule.episodePattern, text: html)
        let values = matches.compactMap { groups -> OnlineEpisode? in
            guard let title = group(groups, result.rule.episodeTitleGroup),
                  let rawURL = group(groups, result.rule.episodeURLGroup),
                  let url = result.rule.absoluteURL(rawURL) else { return nil }
            return OnlineEpisode(title: cleanHTML(title), pageURL: url, rule: result.rule)
        }
        guard !values.isEmpty else { throw OnlineVideoRuleError.noEpisodes }
        return values
    }

    func playableURL(for episode: OnlineEpisode) async throws -> URL {
        if ["m3u8", "mp4"].contains(episode.pageURL.pathExtension.lowercased()) {
            return episode.pageURL
        }
        let html = try await fetchText(url: episode.pageURL, rule: episode.rule, referer: nil)
        for groups in captures(pattern: episode.rule.videoPattern, text: html) {
            guard let raw = group(groups, episode.rule.videoURLGroup),
                  let url = episode.rule.absoluteURL(raw) else { continue }
            return url
        }
        throw OnlineVideoRuleError.noPlayableURL
    }

    private func search(keyword: String, rule: OnlineVideoRule) async throws -> [OnlineAnimeResult] {
        guard let url = rule.searchRequestURL(keyword: keyword) else { return [] }
        if ["m3u8", "mp4"].contains(url.pathExtension.lowercased()) {
            return [OnlineAnimeResult(title: rule.name, detailURL: url, coverURL: nil, rule: rule)]
        }
        let html = try await fetchText(url: url, rule: rule, referer: nil)
        return captures(pattern: rule.resultPattern, text: html).compactMap { groups in
            guard let title = group(groups, rule.titleGroup),
                  let detail = group(groups, rule.detailURLGroup),
                  let detailURL = rule.absoluteURL(detail) else { return nil }
            let coverURL = rule.coverURLGroup.flatMap { group(groups, $0) }.flatMap(rule.absoluteURL)
            return OnlineAnimeResult(title: cleanHTML(title), detailURL: detailURL, coverURL: coverURL, rule: rule)
        }
    }

    private func fetchText(url: URL, rule: OnlineVideoRule, referer: URL?) async throws -> String {
        var request = URLRequest(url: url)
        request.timeoutInterval = 25
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148", forHTTPHeaderField: "User-Agent")
        if let referer { request.setValue(referer.absoluteString, forHTTPHeaderField: "Referer") }
        rule.headers?.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<400).contains(http.statusCode) else {
            throw OnlineVideoRuleError.invalidResponse
        }
        if let text = String(data: data, encoding: .utf8) { return text }
        if let text = String(data: data, encoding: .isoLatin1) { return text }
        throw OnlineVideoRuleError.invalidResponse
    }

    private func captures(pattern: String, text: String) -> [[String?]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).map { match in
            (0..<match.numberOfRanges).map { index in
                let range = match.range(at: index)
                guard range.location != NSNotFound, let swiftRange = Range(range, in: text) else { return nil }
                return String(text[swiftRange])
            }
        }
    }

    private func group(_ groups: [String?], _ index: Int) -> String? {
        guard groups.indices.contains(index) else { return nil }
        return groups[index]
    }

    private func cleanHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
