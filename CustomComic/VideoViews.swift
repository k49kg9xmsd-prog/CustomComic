import SwiftUI
import PhotosUI
import AVKit

struct VideoLibraryView: View {
    @EnvironmentObject private var videoLibrary: VideoLibrary
    @State private var showingSource = false
    @State private var showingFilePicker = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showingPhotoPicker = false
    @State private var showingHiddenLibrary = false
    @State private var isImporting = false
    @State private var errorMessage: String?
    @State private var searchText = ""

    private let columns = [GridItem(.adaptive(minimum: 145, maximum: 190), spacing: 18)]

    private var filteredVideos: [VideoItem] {
        let source = videoLibrary.visibleVideos
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return source }
        return source.filter {
            $0.title.localizedCaseInsensitiveContains(keyword) ||
            $0.category.localizedCaseInsensitiveContains(keyword)
        }
    }

    private var visibleCategories: [String] {
        videoLibrary.categories.filter { category in
            filteredVideos.contains { $0.category == category }
        }
    }

    var body: some View {
        Group {
            if videoLibrary.visibleVideos.isEmpty {
                VideoEmptyLibraryView(isImporting: isImporting)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 28) {
                        if searchText.isEmpty && !videoLibrary.recentlyWatchedVideos.isEmpty {
                            HorizontalVideoSection(
                                title: "繼續觀看",
                                videos: Array(videoLibrary.recentlyWatchedVideos.prefix(8))
                            )
                        }

                        if searchText.isEmpty {
                            let favorites = videoLibrary.visibleVideos.filter(\.isFavorite)
                            if !favorites.isEmpty {
                                HorizontalVideoSection(title: "我的收藏", videos: favorites)
                            }
                        }

                        ForEach(visibleCategories, id: \.self) { category in
                            VStack(alignment: .leading, spacing: 12) {
                                Text(category)
                                    .font(.title2.bold())
                                    .padding(.horizontal)

                                LazyVGrid(columns: columns, spacing: 22) {
                                    ForEach(filteredVideos.filter { $0.category == category }) { item in
                                        VideoNavigationCard(item: item)
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                    }
                    .padding(.vertical)
                }
            }
        }
        .navigationTitle("自訂動畫庫")
        .searchable(text: $searchText, prompt: "搜尋作品或分類")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { showingHiddenLibrary = true } label: { Image(systemName: "lock") }
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
        .fullScreenCover(isPresented: $showingHiddenLibrary) { HiddenVideoLibraryView() }
        .alert("匯入失敗", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("好", role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
    }

    private func importFiles(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
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

struct VideoEmptyLibraryView: View {
    let isImporting: Bool
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "play.rectangle")
                .font(.system(size: 58))
                .foregroundStyle(.secondary)
            Text("還沒有內容").font(.title2.bold())
            Text("按右上角新增，可以從檔案或相簿選擇影片")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if isImporting { ProgressView("正在匯入影片…") }
        }
        .padding(32)
    }
}

struct HorizontalVideoSection: View {
    let title: String
    let videos: [VideoItem]
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.title2.bold()).padding(.horizontal)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 16) {
                    ForEach(videos) { VideoNavigationCard(item: $0) }
                }
                .padding(.horizontal)
            }
        }
    }
}

struct VideoNavigationCard: View {
    @EnvironmentObject private var videoLibrary: VideoLibrary
    let item: VideoItem
    @State private var showingEdit = false

    var body: some View {
        NavigationLink {
            VideoPlayerScreen(item: item)
        } label: {
            VideoCard(item: item)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { videoLibrary.toggleFavorite(item) } label: {
                Label(item.isFavorite ? "取消收藏" : "加入收藏", systemImage: item.isFavorite ? "star.slash" : "star")
            }
            Button { showingEdit = true } label: { Label("編輯資料", systemImage: "pencil") }
            Button { videoLibrary.toggleHidden(item) } label: { Label("移到隱藏庫", systemImage: "lock") }
            Button(role: .destructive) { videoLibrary.delete(item) } label: { Label("刪除影片", systemImage: "trash") }
        }
        .sheet(isPresented: $showingEdit) { EditVideoMetadataView(item: item) }
    }
}

struct VideoCard: View {
    @EnvironmentObject private var videoLibrary: VideoLibrary
    let item: VideoItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                LocalImage(url: videoLibrary.coverURL(for: item), contentMode: .fill)
                    .frame(width: 170, height: 226)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .overlay(Image(systemName: "play.fill").font(.title).padding(12).background(.ultraThinMaterial, in: Circle()))
                    .shadow(radius: 8, y: 4)
                if item.isFavorite {
                    Image(systemName: "star.fill").foregroundStyle(.yellow).padding(10)
                }
            }
            Text(item.title).font(.headline).lineLimit(2).frame(width: 170, alignment: .leading)
            Text(item.category).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(width: 170, alignment: .leading)
    }
}

struct EditVideoMetadataView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var videoLibrary: VideoLibrary
    let item: VideoItem
    @State private var title: String
    @State private var category: String

    init(item: VideoItem) {
        self.item = item
        _title = State(initialValue: item.title)
        _category = State(initialValue: item.category)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("作品名稱", text: $title)
                TextField("分類", text: $category)
            }
            .navigationTitle("編輯動畫")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("儲存") {
                        videoLibrary.updateMetadata(item, title: title, category: category)
                        dismiss()
                    }
                }
            }
        }
    }
}

struct HiddenVideoLibraryView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var videoLibrary: VideoLibrary
    private let columns = [GridItem(.adaptive(minimum: 145, maximum: 190), spacing: 18)]

    var body: some View {
        NavigationStack {
            Group {
                if videoLibrary.hiddenVideos.isEmpty {
                    VStack(spacing: 14) {
                        Image(systemName: "lock.open").font(.system(size: 54)).foregroundStyle(.secondary)
                        Text("隱藏庫沒有內容").font(.title2.bold())
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 22) {
                            ForEach(videoLibrary.hiddenVideos) { item in
                                VideoNavigationCard(item: item)
                                    .contextMenu {
                                        Button { videoLibrary.toggleHidden(item) } label: {
                                            Label("移回動畫庫", systemImage: "lock.open")
                                        }
                                    }
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("隱藏動畫庫")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
        }
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
            .onAppear { videoLibrary.markWatched(item) }
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
