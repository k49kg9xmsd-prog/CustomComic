import SwiftUI

struct IPADetailView: View {
    @EnvironmentObject private var library: IPALibrary
    let item: IPAItem
    @Binding var shareURL: URL?

    var body: some View {
        List {
            Section {
                HStack(spacing: 18) {
                    IPAIcon(url: library.iconURL(for: item), size: 88)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.displayName).font(.title2.bold())
                        Text(item.bundleIdentifier).font(.footnote).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                }.padding(.vertical, 8)
            }
            Section("App 資訊") {
                LabeledContent("版本", value: item.version)
                LabeledContent("Build", value: item.build)
                LabeledContent("大小", value: item.formattedSize)
                LabeledContent("匯入時間", value: item.importedAt.formatted(date: .abbreviated, time: .shortened))
            }
            Section {
                Button { shareURL = library.fileURL(for: item) } label: { Label("分享／傳送到安裝器", systemImage: "square.and.arrow.up") }
                ShareLink(item: library.fileURL(for: item)) { Label("使用系統分享", systemImage: "arrow.up.doc") }
            } footer: {
                Text("在分享選單中選擇 SideStore、TrollStore、檔案或其他支援 IPA 的工具。")
            }
        }
        .navigationTitle("App 詳細資料")
        .navigationBarTitleDisplayMode(.inline)
    }
}
