import SwiftUI
import WebKit

@MainActor
final class WebsiteStore: ObservableObject {
    @Published var websites: [SavedWebsite] = []
    private let url: URL

    init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        url = documents.appendingPathComponent("websites.json")
        load()
    }

    func add(name: String, urlString: String) {
        let cleaned = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        let final = cleaned.hasPrefix("http://") || cleaned.hasPrefix("https://")
            ? cleaned
            : "https://\(cleaned)"
        websites.append(
            SavedWebsite(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? final
                    : name,
                urlString: final
            )
        )
        save()
    }

    func delete(at offsets: IndexSet) {
        websites.remove(atOffsets: offsets)
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([SavedWebsite].self, from: data)
        else { return }
        websites = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(websites) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

struct WebsiteListView: View {
    @EnvironmentObject private var websiteStore: WebsiteStore
    @EnvironmentObject private var downloadManager: DownloadManager
    @State private var showingAdd = false
    @State private var showingDownloads = false

    var body: some View {
        List {
            Section {
                Text("登入狀態會由內建瀏覽器保留。網站的帳號密碼仍由網站自己處理，本 App 不會讀取密碼。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("已儲存網站") {
                ForEach(websiteStore.websites) { website in
                    NavigationLink {
                        BrowserView(website: website)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(website.name)
                            Text(website.urlString)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .onDelete(perform: websiteStore.delete)
            }

            Section {
                Button {
                    showingAdd = true
                } label: {
                    Label("新增網站", systemImage: "plus")
                }

                Button {
                    showingDownloads = true
                } label: {
                    Label("下載管理", systemImage: "arrow.down.circle")
                }
            }
        }
        .sheet(isPresented: $showingAdd) {
            AddWebsiteView()
        }
        .sheet(isPresented: $showingDownloads) {
            DownloadListView()
        }
    }
}

struct AddWebsiteView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var websiteStore: WebsiteStore
    @State private var name = ""
    @State private var url = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("網站名稱", text: $name)
                TextField("網址", text: $url)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            .navigationTitle("新增網站")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("儲存") {
                        websiteStore.add(name: name, urlString: url)
                        dismiss()
                    }
                    .disabled(url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

struct BrowserView: View {
    let website: SavedWebsite
    @EnvironmentObject private var downloadManager: DownloadManager
    @State private var currentURL: URL?
    @State private var cookieHeader = ""
    @State private var browserUserAgent = ""
    @State private var directURLText = ""
    @State private var showingDownloadPrompt = false

    var body: some View {
        WebView(
            initialURL: URL(string: website.urlString)!,
            currentURL: $currentURL,
            cookieHeader: $cookieHeader,
            userAgent: $browserUserAgent
        )
        .navigationTitle(website.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    directURLText = currentURL?.absoluteString ?? ""
                    showingDownloadPrompt = true
                } label: {
                    Image(systemName: "arrow.down.circle")
                }

                if let currentURL {
                    ShareLink(item: currentURL) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
        .alert("下載連結", isPresented: $showingDownloadPrompt) {
            TextField("直接檔案或圖片網址", text: $directURLText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("開始下載") {
                if let url = URL(string: directURLText) {
                    downloadManager.start(
                        url: url,
                        cookieHeader: cookieHeader,
                        referer: currentURL,
                        userAgent: browserUserAgent
                    )
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("目前先支援直接檔案、ZIP、CBZ或圖片網址。需要登入的連結會沿用網站的登入狀態瀏覽，但部分網站仍可能禁止下載。")
        }
    }
}

struct WebView: UIViewRepresentable {
    let initialURL: URL
    @Binding var currentURL: URL?
    @Binding var cookieHeader: String
    @Binding var userAgent: String

    func makeCoordinator() -> Coordinator {
        Coordinator(
            currentURL: $currentURL,
            cookieHeader: $cookieHeader,
            userAgent: $userAgent
        )
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.allowsInlineMediaPlayback = true

        let web = WKWebView(frame: .zero, configuration: configuration)
        web.navigationDelegate = context.coordinator
        web.allowsBackForwardNavigationGestures = true
        web.load(URLRequest(url: initialURL))
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        @Binding var currentURL: URL?
        @Binding var cookieHeader: String
        @Binding var userAgent: String

        init(
            currentURL: Binding<URL?>,
            cookieHeader: Binding<String>,
            userAgent: Binding<String>
        ) {
            _currentURL = currentURL
            _cookieHeader = cookieHeader
            _userAgent = userAgent
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            currentURL = webView.url

            webView.evaluateJavaScript("navigator.userAgent") { result, _ in
                if let result = result as? String {
                    DispatchQueue.main.async {
                        self.userAgent = result
                    }
                }
            }

            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies {
                cookies in
                let header = HTTPCookie.requestHeaderFields(
                    with: cookies
                )["Cookie"] ?? ""

                DispatchQueue.main.async {
                    self.cookieHeader = header
                }
            }
        }
    }
}

struct DownloadListView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var downloadManager: DownloadManager

    var body: some View {
        NavigationStack {
            List(downloadManager.records) { record in
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text(record.title)
                            .lineLimit(1)
                        Spacer()
                        Text(statusText(record.status))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    ProgressView(value: record.progress)

                    if let error = record.errorText {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    if record.status == .downloading || record.status == .waiting {
                        Button("取消下載", role: .destructive) {
                            downloadManager.cancel(record)
                        }
                        .font(.caption)
                    }
                }
                .padding(.vertical, 4)
            }
            .navigationTitle("下載管理")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private func statusText(_ status: DownloadRecord.Status) -> String {
        switch status {
        case .waiting: return "等待中"
        case .downloading: return "下載中"
        case .finished: return "完成"
        case .failed: return "失敗"
        case .cancelled: return "已取消"
        }
    }
}
