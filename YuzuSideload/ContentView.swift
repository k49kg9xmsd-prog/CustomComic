import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var library: IPALibrary
    @State private var showingImporter = false
    @State private var shareURL: URL?
    @State private var query = ""

    private var filteredItems: [IPAItem] {
        guard !query.isEmpty else { return library.items }
        return library.items.filter {
            $0.displayName.localizedCaseInsensitiveContains(query) ||
            $0.bundleIdentifier.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if library.items.isEmpty { emptyState } else { appList }
            }
            .navigationTitle("柚子側載")
            .searchable(text: $query, prompt: "搜尋名稱或 Bundle ID")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showingImporter = true } label: { Label("匯入 IPA", systemImage: "plus") }
                }
            }
            .sheet(isPresented: $showingImporter) {
                IPADocumentPicker { url in
                    showingImporter = false
                    Task { await library.importIPA(from: url) }
                }
            }
            .sheet(item: Binding(get: { shareURL.map(ShareURL.init) }, set: { if $0 == nil { shareURL = nil } })) { value in
                ShareSheet(items: [value.url])
            }
            .alert("匯入失敗", isPresented: Binding(get: { library.lastError != nil }, set: { if !$0 { library.lastError = nil } })) {
                Button("好", role: .cancel) {}
            } message: { Text(library.lastError ?? "未知錯誤") }
            .overlay { if library.isImporting { ProgressView("正在分析 IPA…").padding(22).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18)) } }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("還沒有 IPA", systemImage: "shippingbox")
        } description: {
            Text("匯入 IPA 後，可查看 App 資訊並分享給 SideStore、TrollStore 或其他安裝器。")
        } actions: {
            Button("匯入 IPA") { showingImporter = true }.buttonStyle(.borderedProminent)
        }
    }

    private var appList: some View {
        List {
            Section {
                ForEach(filteredItems) { item in
                    NavigationLink { IPADetailView(item: item, shareURL: $shareURL) } label: { IPARow(item: item) }
                        .swipeActions { Button(role: .destructive) { library.delete(item) } label: { Label("刪除", systemImage: "trash") } }
                }
            } footer: {
                Text("本 App 只管理與轉交 IPA；一般 iOS 裝置仍需由 SideStore 等工具簽署後安裝，相容 TrollStore 的系統可永久安裝。")
            }
        }
    }
}

private struct ShareURL: Identifiable { let id = UUID(); let url: URL }

struct IPARow: View {
    @EnvironmentObject private var library: IPALibrary
    let item: IPAItem
    var body: some View {
        HStack(spacing: 14) {
            IPAIcon(url: library.iconURL(for: item), size: 58)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.displayName).font(.headline).lineLimit(1)
                Text(item.bundleIdentifier).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Text("v\(item.version) (\(item.build)) · \(item.formattedSize)").font(.caption2).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 4)
    }
}

struct IPAIcon: View {
    let url: URL?
    let size: CGFloat
    var body: some View {
        Group {
            if let url, let image = UIImage(contentsOfFile: url.path) { Image(uiImage: image).resizable().scaledToFill() }
            else { Image(systemName: "app.dashed").resizable().scaledToFit().padding(size * 0.22).foregroundStyle(.secondary).background(.quaternary) }
        }
        .frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
    }
}
