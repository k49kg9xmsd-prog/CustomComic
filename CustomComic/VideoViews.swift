import SwiftUI
import PhotosUI
import AVKit
import UniformTypeIdentifiers

struct VideoLibraryView: View {
    @EnvironmentObject private var videoLibrary: VideoLibrary
    @State private var showingImport = false
    @State private var showingHiddenLibrary = false
    @State private var searchText = ""
    @State private var showingBatchManager = false

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
                VideoEmptyLibraryView(isImporting: false)
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
        .searchable(text: $searchText, prompt: "搜尋作品、分類或集數")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { showingBatchManager = true } label: { Image(systemName: "checkmark.circle") }
                Button { showingHiddenLibrary = true } label: { Image(systemName: "lock") }
                Button { showingImport = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showingImport) { ImportVideoSeriesView() }
        .sheet(isPresented: $showingBatchManager) { VideoBatchManagerView() }
        .fullScreenCover(isPresented: $showingHiddenLibrary) { HiddenVideoLibraryView() }
    }
}

struct ImportVideoSeriesView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var videoLibrary: VideoLibrary

    @State private var title = ""
    @State private var selectedCategory = "未分類"
    @State private var newCategoryName = ""
    @State private var showingNewCategoryField = false
    @State private var videoFiles: [URL] = []
    @State private var episodeTitles: [String] = []
    @State private var showingSource = false
    @State private var showingVideoPicker = false
    @State private var showingPhotoPicker = false
    @State private var videoPhotoItems: [PhotosPickerItem] = []
    @State private var coverPhotoItem: PhotosPickerItem?
    @State private var coverData: Data?
    @State private var isImporting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("作品資料") {
                    TextField("作品名稱", text: $title)

                    Picker("分類", selection: $selectedCategory) {
                        Text("＋ 建立新分類").tag("__CREATE_NEW__")
                        ForEach(videoLibrary.categories.isEmpty ? ["未分類"] : videoLibrary.categories, id: \.self) {
                            Text($0).tag($0)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: selectedCategory) {
                        showingNewCategoryField = $0 == "__CREATE_NEW__"
                    }

                    if showingNewCategoryField {
                        TextField("新分類名稱", text: $newCategoryName)
                    }

                    Button { showingSource = true } label: {
                        HStack {
                            Label("選擇一個以上的影片", systemImage: "film.stack")
                            Spacer()
                            Text(videoFiles.isEmpty ? "未選擇" : "\(videoFiles.count) 個")
                                .foregroundStyle(.secondary)
                        }
                    }

                    PhotosPicker(selection: $coverPhotoItem, matching: .images) {
                        HStack {
                            Label("從相簿選作品封面", systemImage: "photo")
                            Spacer()
                            Text(coverData == nil ? "使用第一幀" : "已選擇")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if !videoFiles.isEmpty {
                    Section("集數") {
                        ForEach(videoFiles.indices, id: \.self) { index in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(videoFiles[index].lastPathComponent)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                TextField("集數名稱", text: Binding(
                                    get: { episodeTitles[index] },
                                    set: { episodeTitles[index] = $0 }
                                ))
                            }
                        }
                    }
                }

                Section {
                    Button(action: importSeries) {
                        if isImporting {
                            HStack { Spacer(); ProgressView(); Text("正在匯入…"); Spacer() }
                        } else {
                            Text("建立作品").frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(videoFiles.isEmpty || isImporting || (showingNewCategoryField && newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
                } footer: {
                    Text("一次選多個影片時，每個影片會成為一集，也可以自行修改集數名稱。")
                }
            }
            .navigationTitle("建立新作品")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            }
            .confirmationDialog("選擇影片來源", isPresented: $showingSource, titleVisibility: .visible) {
                Button("從檔案選擇") { showingVideoPicker = true }
                Button("從相簿選擇") { showingPhotoPicker = true }
                Button("取消", role: .cancel) {}
            }
            .sheet(isPresented: $showingVideoPicker) {
                VideoFilePicker { urls in
                    setVideos(urls)
                    showingVideoPicker = false
                }
            }
            .photosPicker(isPresented: $showingPhotoPicker, selection: $videoPhotoItems, maxSelectionCount: nil, matching: .videos)
            .onChange(of: videoPhotoItems) { items in loadVideoPhotos(items) }
            .onChange(of: coverPhotoItem) { item in loadCover(item) }
            .alert("建立失敗", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("好", role: .cancel) {}
            } message: { Text(errorMessage ?? "") }
        }
    }

    private func setVideos(_ urls: [URL]) {
        videoFiles = urls.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        episodeTitles = videoFiles.enumerated().map { index, url in
            let guessed = url.deletingPathExtension().lastPathComponent
            return guessed.isEmpty ? "第 \(index + 1) 集" : guessed
        }
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let first = videoFiles.first {
            title = first.deletingPathExtension().lastPathComponent
        }
    }

    private func loadVideoPhotos(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        Task {
            do {
                var urls: [URL] = []
                for item in items {
                    guard let data = try await item.loadTransferable(type: Data.self) else { continue }
                    let url = FileManager.default.temporaryDirectory.appendingPathComponent("video-\(UUID().uuidString).mov")
                    try data.write(to: url, options: .atomic)
                    urls.append(url)
                }
                setVideos(urls)
                videoPhotoItems = []
            } catch { errorMessage = error.localizedDescription }
        }
    }

    private func loadCover(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            do { coverData = try await item.loadTransferable(type: Data.self) }
            catch { errorMessage = error.localizedDescription }
        }
    }

    private func importSeries() {
        isImporting = true
        let category = showingNewCategoryField ? newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines) : selectedCategory
        Task {
            do {
                try await videoLibrary.importSeries(
                    urls: videoFiles,
                    seriesTitle: title,
                    episodeTitles: episodeTitles,
                    category: category,
                    coverData: coverData
                )
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isImporting = false
            }
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
    @State private var exportURL: URL?

    var body: some View {
        NavigationLink {
            VideoDetailView(itemID: item.id)
        } label: {
            VideoCard(item: item)
                .contentShape(Rectangle())
        }
        .frame(width: 170, alignment: .leading)
        .contentShape(Rectangle())
        .buttonStyle(.plain)
        .contextMenu {
            Button { videoLibrary.toggleFavorite(item) } label: {
                Label(item.isFavorite ? "取消收藏" : "加入收藏", systemImage: item.isFavorite ? "star.slash" : "star")
            }
            Button { showingEdit = true } label: { Label("編輯資料", systemImage: "pencil") }
            Button { videoLibrary.toggleHidden(item) } label: { Label("移到隱藏庫", systemImage: "lock") }
            Button { exportURL = videoLibrary.exportURL(for: item) } label: { Label("匯出影片", systemImage: "square.and.arrow.up") }
            Button(role: .destructive) { videoLibrary.delete(item) } label: { Label("刪除影片", systemImage: "trash") }
        }
        .sheet(isPresented: $showingEdit) { EditVideoMetadataView(item: item) }
        .sheet(item: Binding(get: { exportURL.map { VideoExportURL(value: $0) } }, set: { exportURL = $0?.value })) { value in
            ActivityShareSheet(items: [value.value])
        }
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
                    .allowsHitTesting(false)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .overlay(Image(systemName: "play.fill").font(.title).padding(12).background(.ultraThinMaterial, in: Circle()).allowsHitTesting(false))
                    .shadow(radius: 8, y: 4)
                if item.isFavorite {
                    Image(systemName: "star.fill").foregroundStyle(.yellow).padding(10)
                }
                VStack {
                    Spacer()
                    HStack {
                        Text(item.progressFraction >= 0.95 ? "✓ 已看" : (item.lastPosition > 1 ? "◐ 觀看中" : "○ 未看"))
                            .font(.caption2.bold())
                            .padding(.horizontal, 8).padding(.vertical, 5)
                            .background(.ultraThinMaterial, in: Capsule())
                        Spacer()
                    }.padding(8)
                }
            }
            Text(item.title).font(.headline).lineLimit(2).frame(width: 170, alignment: .leading)
            Text(item.category).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(width: 170, alignment: .leading)
        .contentShape(Rectangle())
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

struct VideoDetailView: View {
    @EnvironmentObject private var videoLibrary: VideoLibrary
    @Environment(\.dismiss) private var dismiss
    let itemID: UUID
    @State private var showingEdit = false
    @State private var showingPlayer = false

    private var item: VideoItem? { videoLibrary.videos.first { $0.id == itemID } }

    var body: some View {
        Group {
            if let item {
                List {
                    Section {
                        HStack(alignment: .top, spacing: 18) {
                            LocalImage(url: videoLibrary.coverURL(for: item), contentMode: .fill)
                                .frame(width: 120, height: 165)
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                            VStack(alignment: .leading, spacing: 10) {
                                Text(item.title).font(.title2.bold())
                                Text(item.category).font(.caption).padding(.horizontal, 9).padding(.vertical, 4).background(.secondary.opacity(0.15), in: Capsule())
                                Text(item.progressText).foregroundStyle(.secondary).monospacedDigit()
                                if item.duration > 0 {
                                    ProgressView(value: item.progressFraction)
                                }
                                Button {
                                    showingPlayer = true
                                } label: {
                                    Label(item.lastPosition > 1 ? "繼續觀看" : "開始觀看", systemImage: "play.fill")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    Section("作品資料") {
                        LabeledContent("名稱", value: item.title)
                        LabeledContent("分類", value: item.category)
                        LabeledContent("觀看進度", value: item.progressText)
                        LabeledContent("加入日期", value: item.createdAt.formatted(date: .abbreviated, time: .omitted))
                    }
                    Section {
                        Button { videoLibrary.toggleFavorite(item) } label: {
                            Label(item.isFavorite ? "取消收藏" : "加入收藏", systemImage: item.isFavorite ? "star.slash" : "star")
                        }
                        Button { showingEdit = true } label: { Label("編輯資料", systemImage: "pencil") }
                        if item.lastPosition > 0 {
                            Button { videoLibrary.resetProgress(item) } label: { Label("清除觀看進度", systemImage: "arrow.counterclockwise") }
                        }
                        Button(role: .destructive) {
                            videoLibrary.delete(item)
                            dismiss()
                        } label: { Label("刪除作品", systemImage: "trash") }
                    }
                }
                .navigationTitle(item.title)
                .navigationBarTitleDisplayMode(.inline)
                .sheet(isPresented: $showingEdit) { EditVideoMetadataView(item: item) }
                .fullScreenCover(isPresented: $showingPlayer) { NavigationStack { VideoPlayerScreen(itemID: item.id) } }
            } else {
                VStack(spacing: 12) { Image(systemName: "exclamationmark.triangle").font(.largeTitle); Text("找不到作品").font(.headline) }
            }
        }
    }
}

struct VideoPlayerScreen: View {
    let itemID: UUID

    var body: some View {
        YuzuPlayerScreen(itemID: itemID)
    }
}

struct VideoBatchManagerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var videoLibrary: VideoLibrary
    @State private var selected = Set<UUID>()
    @State private var category = ""
    @State private var showingDelete = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(videoLibrary.visibleVideos) { item in
                        Button {
                            if selected.contains(item.id) { selected.remove(item.id) } else { selected.insert(item.id) }
                        } label: {
                            HStack {
                                Image(systemName: selected.contains(item.id) ? "checkmark.circle.fill" : "circle")
                                VStack(alignment: .leading) { Text(item.title); Text(item.category).font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                if !selected.isEmpty {
                    Section("批次操作") {
                        TextField("移動到分類", text: $category)
                        Button("套用分類") { videoLibrary.batchSetCategory(ids: selected, category: category); selected.removeAll() }
                        Button("移到隱藏庫") { videoLibrary.batchSetHidden(ids: selected, hidden: true); selected.removeAll() }
                        Button("刪除已選作品", role: .destructive) { showingDelete = true }
                    }
                }
            }
            .navigationTitle("批次管理")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("全選") { selected = Set(videoLibrary.visibleVideos.map(\.id)) } }
                ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } }
            }
            .confirmationDialog("確定刪除已選作品？", isPresented: $showingDelete) {
                Button("刪除", role: .destructive) { videoLibrary.batchDelete(ids: selected); selected.removeAll() }
            }
        }
    }
}

struct OnlineVideoImportView: View {
    @StateObject private var ruleStore = OnlineVideoRuleStore()
    @State private var keyword = ""
    @State private var results: [OnlineAnimeResult] = []
    @State private var selectedResult: OnlineAnimeResult?
    @State private var episodes: [OnlineEpisode] = []
    @State private var selectedEpisode: OnlineEpisode?
    @State private var playableURL: URL?
    @State private var isSearching = false
    @State private var isLoadingEpisodes = false
    @State private var isResolving = false
    @State private var showingRuleImporter = false
    @State private var showingRules = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("搜尋動畫") {
                TextField("輸入作品名稱", text: $keyword)
                    .textInputAutocapitalization(.never)
                    .submitLabel(.search)
                    .onSubmit(search)

                Button(isSearching ? "搜尋中…" : "搜尋") { search() }
                    .disabled(isSearching || keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || ruleStore.rules.isEmpty)
            }

            if ruleStore.rules.isEmpty {
                Section("來源規則") {
                    ContentUnavailableView(
                        "尚未匯入來源規則",
                        systemImage: "puzzlepiece.extension",
                        description: Text("匯入 JSON 規則後，App 才能依規則搜尋、取得集數並解析播放網址。")
                    )
                    Button("匯入規則") { showingRuleImporter = true }
                }
            } else {
                Section("搜尋來源") {
                    Button("已啟用 \(ruleStore.rules.count) 個來源") { showingRules = true }
                    Button("匯入更多規則") { showingRuleImporter = true }
                }
            }

            if !results.isEmpty {
                Section("搜尋結果") {
                    ForEach(results) { result in
                        Button {
                            selectedResult = result
                            loadEpisodes(result)
                        } label: {
                            HStack(spacing: 12) {
                                AsyncImage(url: result.coverURL) { image in
                                    image.resizable().scaledToFill()
                                } placeholder: {
                                    Color.secondary.opacity(0.15)
                                }
                                .frame(width: 58, height: 78)
                                .clipShape(RoundedRectangle(cornerRadius: 8))

                                VStack(alignment: .leading, spacing: 5) {
                                    Text(result.title).foregroundStyle(.primary)
                                    Text(result.rule.name).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if isLoadingEpisodes && selectedResult?.id == result.id { ProgressView() }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if !episodes.isEmpty {
                Section(selectedResult?.title ?? "集數") {
                    ForEach(episodes) { episode in
                        Button {
                            selectedEpisode = episode
                            resolve(episode)
                        } label: {
                            HStack {
                                Text(episode.title).foregroundStyle(.primary)
                                Spacer()
                                if isResolving && selectedEpisode?.id == episode.id { ProgressView() }
                                else { Image(systemName: "play.circle") }
                            }
                        }
                    }
                }
            }

            Section {
                Text("規則只描述搜尋頁、作品頁、集數與播放網址的位置；介面與播放器仍使用本 App 原本的設計。請只匯入你有權使用的來源規則。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("線上動畫")
        .fileImporter(
            isPresented: $showingRuleImporter,
            allowedContentTypes: [.json, .plainText],
            allowsMultipleSelection: false
        ) { result in
            do {
                guard let url = try result.get().first else { return }
                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                try ruleStore.importRules(from: Data(contentsOf: url))
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        .sheet(isPresented: $showingRules) {
            NavigationStack {
                List {
                    ForEach(ruleStore.rules) { rule in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(rule.name)
                            Text(rule.baseURL).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .onDelete(perform: ruleStore.remove)
                }
                .navigationTitle("來源規則")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("完成") { showingRules = false }
                    }
                }
            }
        }
        .fullScreenCover(item: Binding(
            get: { playableURL.map { RemotePlayableURL(url: $0) } },
            set: { playableURL = $0?.url }
        )) { item in
            RemoteVideoPlayer(url: item.url)
        }
        .alert("處理失敗", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func search() {
        let value = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        isSearching = true
        results = []
        episodes = []
        Task {
            do {
                results = try await OnlineVideoRuleEngine.shared.search(keyword: value, rules: ruleStore.rules)
            } catch {
                errorMessage = error.localizedDescription
            }
            isSearching = false
        }
    }

    private func loadEpisodes(_ result: OnlineAnimeResult) {
        isLoadingEpisodes = true
        episodes = []
        Task {
            do {
                episodes = try await OnlineVideoRuleEngine.shared.episodes(for: result)
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoadingEpisodes = false
        }
    }

    private func resolve(_ episode: OnlineEpisode) {
        isResolving = true
        Task {
            do {
                playableURL = try await OnlineVideoRuleEngine.shared.playableURL(for: episode)
            } catch {
                errorMessage = error.localizedDescription
            }
            isResolving = false
        }
    }
}

private struct RemotePlayableURL: Identifiable {
    let id = UUID()
    let url: URL
}

private struct RemoteVideoPlayer: View {
    @Environment(\.dismiss) private var dismiss
    let url: URL
    @State private var player: AVPlayer

    init(url: URL) {
        self.url = url
        _player = State(initialValue: AVPlayer(url: url))
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            VideoPlayer(player: player).ignoresSafeArea()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .padding()
        }
        .onAppear { player.play() }
        .onDisappear { player.pause() }
    }
}

private struct VideoExportURL: Identifiable { let id = UUID(); let value: URL }
