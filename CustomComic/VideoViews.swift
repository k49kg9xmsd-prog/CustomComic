import SwiftUI
import PhotosUI
import AVKit

struct VideoLibraryView: View {
    @EnvironmentObject private var videoLibrary: VideoLibrary
    @State private var showingSource = false
    @State private var showingFilePicker = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showingPhotoPicker = false
    @State private var isImporting = false
    @State private var errorMessage: String?

    private let columns = [GridItem(.adaptive(minimum: 145, maximum: 190), spacing: 18)]

    var body: some View {
        Group {
            if videoLibrary.videos.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "play.rectangle")
                        .font(.system(size: 56))
                        .foregroundStyle(.secondary)
                    Text("還沒有動畫").font(.title2.bold())
                    Text("按右上角＋上傳影片").foregroundStyle(.secondary)
                    if isImporting { ProgressView("正在匯入影片…") }
                }
                .padding(32)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 22) {
                        ForEach(videoLibrary.videos) { item in
                            NavigationLink {
                                VideoPlayerScreen(item: item)
                            } label: {
                                VideoCard(item: item)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button(role: .destructive) { videoLibrary.delete(item) } label: {
                                    Label("刪除影片", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("自訂動畫庫")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingSource = true } label: { Image(systemName: "plus") }
                    .disabled(isImporting)
            }
        }
        .confirmationDialog("上傳影片", isPresented: $showingSource, titleVisibility: .visible) {
            Button("從檔案選擇") { showingFilePicker = true }
            Button("從相簿選擇") { showingPhotoPicker = true }
            Button("取消", role: .cancel) {}
        }
        .sheet(isPresented: $showingFilePicker) {
            VideoFilePicker { urls in
                showingFilePicker = false
                importFiles(urls)
            }
        }
        .photosPicker(isPresented: $showingPhotoPicker, selection: $photoItems, maxSelectionCount: nil, matching: .videos)
        .onChange(of: photoItems) { items in importPhotos(items) }
        .alert("匯入失敗", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("好", role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
    }

    private func importFiles(_ urls: [URL]) {
        isImporting = true
        Task {
            do { try await videoLibrary.importFiles(urls) }
            catch { errorMessage = error.localizedDescription }
            isImporting = false
        }
    }

    private func importPhotos(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        isImporting = true
        Task {
            do {
                for item in items {
                    guard let data = try await item.loadTransferable(type: Data.self) else { continue }
                    try await videoLibrary.importPhotoData(data)
                }
            } catch { errorMessage = error.localizedDescription }
            photoItems = []
            isImporting = false
        }
    }
}

struct VideoCard: View {
    @EnvironmentObject private var videoLibrary: VideoLibrary
    let item: VideoItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LocalImage(url: videoLibrary.coverURL(for: item), contentMode: .fill)
                .frame(width: 170, height: 226)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .overlay(Image(systemName: "play.fill").font(.title).padding(12).background(.ultraThinMaterial, in: Circle()))
                .shadow(radius: 8, y: 4)
            Text(item.title).font(.headline).lineLimit(2).frame(width: 170, alignment: .leading)
        }
        .frame(width: 170, alignment: .leading)
    }
}

struct VideoPlayerScreen: View {
    @EnvironmentObject private var videoLibrary: VideoLibrary
    let item: VideoItem
    var body: some View {
        VideoPlayer(player: AVPlayer(url: videoLibrary.videoURL(for: item)))
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle(item.title)
            .navigationBarTitleDisplayMode(.inline)
    }
}

struct OnlineVideoImportView: View {
    @EnvironmentObject private var videoLibrary: VideoLibrary
    @State private var link = ""
    @State private var title = ""
    @State private var coverURL: URL?
    @State private var coverData: Data?
    @State private var isAnalyzing = false
    @State private var isDownloading = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("影片連結") {
                TextField("貼上直接影片網址", text: $link)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                Button(isAnalyzing ? "分析中…" : "分析影片") { analyze() }
                    .disabled(isAnalyzing || URL(string: link) == nil)
            }

            if let coverURL {
                Section("影片資料") {
                    AsyncImage(url: coverURL) { image in image.resizable().scaledToFit() } placeholder: { ProgressView() }
                        .frame(maxHeight: 220)
                    TextField("影片名稱", text: $title)
                    Picker("畫質", selection: .constant("原始畫質")) { Text("原始畫質").tag("原始畫質") }
                    Button(isDownloading ? "下載中…" : "下載並加入動畫庫") { download() }
                        .disabled(isDownloading)
                }
            }

            Section {
                Text("目前支援可直接下載的 MP4、MOV、M4V 等公開影片網址；受 DRM 保護的影片無法下載。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("線上動畫")
        .alert("處理失敗", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("好", role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
    }

    private func analyze() {
        guard let url = URL(string: link) else { return }
        isAnalyzing = true
        Task {
            do {
                var request = URLRequest(url: url)
                request.httpMethod = "HEAD"
                let (_, response) = try await URLSession.shared.data(for: request)
                let suggested = response.suggestedFilename ?? url.lastPathComponent
                title = suggested.isEmpty ? "線上影片" : URL(fileURLWithPath: suggested).deletingPathExtension().lastPathComponent
                coverURL = url
                coverData = nil
            } catch { errorMessage = error.localizedDescription }
            isAnalyzing = false
        }
    }

    private func download() {
        guard let url = URL(string: link) else { return }
        isDownloading = true
        Task {
            do { try await videoLibrary.downloadDirectVideo(from: url, title: title, coverData: coverData) }
            catch { errorMessage = error.localizedDescription }
            isDownloading = false
        }
    }
}
