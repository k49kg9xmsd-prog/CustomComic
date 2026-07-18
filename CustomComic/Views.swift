import SwiftUI
import PhotosUI

struct RootView: View {
    @State private var selectedTab = LibraryTab.local
    @State private var showingSettings = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackgroundView()

                VStack(spacing: 0) {
                    Picker("內容", selection: $selectedTab) {
                        ForEach(LibraryTab.allCases) { tab in
                            Text(tab.title).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.top, 8)

                    Group {
                        if selectedTab == .local {
                            LibraryView()
                        } else {
                            WebsiteListView()
                        }
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showingSettings) {
                AppSettingsView()
            }
        }
    }
}


struct LibraryView: View {
    @EnvironmentObject private var library: ComicLibrary
    @State private var showingImport = false
    @State private var showingHiddenLibrary = false
    @State private var searchText = ""
    @State private var addEpisodeTarget: ComicBook?

    private let columns = [GridItem(.adaptive(minimum: 145, maximum: 190), spacing: 18)]

    private var filteredBooks: [ComicBook] {
        let source = library.visibleBooks
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return source
        }
        return source.filter { book in
            book.title.localizedCaseInsensitiveContains(searchText) ||
            book.category.localizedCaseInsensitiveContains(searchText) ||
            book.episodes.contains {
                $0.title.localizedCaseInsensitiveContains(searchText)
            }
        }
    }

    private var visibleCategories: [String] {
        library.categories.filter { category in
            filteredBooks.contains { $0.category == category }
        }
    }

    var body: some View {
            Group {
                if library.visibleBooks.isEmpty {
                    EmptyLibraryView()
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 28) {
                            if searchText.isEmpty && !library.recentlyReadBooks.isEmpty {
                                HorizontalBookSection(
                                    title: "繼續閱讀",
                                    books: Array(library.recentlyReadBooks.prefix(8)),
                                    addEpisodeTarget: $addEpisodeTarget
                                )
                            }

                            if searchText.isEmpty {
                                let favorites = library.visibleBooks.filter(\.isFavorite)
                                if !favorites.isEmpty {
                                    HorizontalBookSection(
                                        title: "我的收藏",
                                        books: favorites,
                                        addEpisodeTarget: $addEpisodeTarget
                                    )
                                }
                            }

                            ForEach(visibleCategories, id: \.self) { category in
                                VStack(alignment: .leading, spacing: 12) {
                                    Text(category)
                                        .font(.title2.bold())
                                        .padding(.horizontal)

                                    LazyVGrid(columns: columns, spacing: 22) {
                                        ForEach(
                                            filteredBooks.filter { $0.category == category }
                                        ) { book in
                                            BookNavigationCard(
                                                book: book,
                                                addEpisodeTarget: $addEpisodeTarget
                                            )
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
            .navigationTitle("自訂漫畫庫")
            .searchable(text: $searchText, prompt: "搜尋作品、分類或集數")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        showingHiddenLibrary = true
                    } label: {
                        Image(systemName: "lock")
                    }

                    Button {
                        showingImport = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingImport) {
                ImportSeriesView()
            }
            .sheet(isPresented: $showingHiddenLibrary) {
                HiddenLibraryView()
            }
            .sheet(item: $addEpisodeTarget) { book in
                AddEpisodesView(book: book)
            }
    }
}

struct HorizontalBookSection: View {
    let title: String
    let books: [ComicBook]
    @Binding var addEpisodeTarget: ComicBook?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title2.bold())
                .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 16) {
                    ForEach(books) { book in
                        BookNavigationCard(
                            book: book,
                            addEpisodeTarget: $addEpisodeTarget
                        )
                        .frame(width: 170)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

struct BookNavigationCard: View {
    @EnvironmentObject private var library: ComicLibrary
    let book: ComicBook
    @Binding var addEpisodeTarget: ComicBook?

    var body: some View {
        NavigationLink {
            SeriesDetailView(bookID: book.id)
        } label: {
            BookCard(book: book)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                addEpisodeTarget = book
            } label: {
                Label("新增集數", systemImage: "plus.rectangle.on.rectangle")
            }

            Button {
                library.toggleFavorite(book)
            } label: {
                Label(
                    book.isFavorite ? "取消收藏" : "加入收藏",
                    systemImage: book.isFavorite ? "star.slash" : "star"
                )
            }

            Menu {
                ForEach(library.categories, id: \.self) { category in
                    Button(category) {
                        library.move(book, to: category)
                    }
                }
            } label: {
                Label("移動分類", systemImage: "folder")
            }

            Button {
                library.setHidden(true, for: book)
            } label: {
                Label("隱藏漫畫", systemImage: "eye.slash")
            }

            Button(role: .destructive) {
                library.delete(book)
            } label: {
                Label("刪除作品", systemImage: "trash")
            }
        }
    }
}

struct EmptyLibraryView: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "books.vertical")
                .font(.system(size: 54))
                .foregroundStyle(.secondary)

            Text("還沒有內容")
                .font(.title2.bold())

            Text("按右上角新增，可以一次選擇多個漫畫 ZIP。")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
    }
}

struct BookCard: View {
    @EnvironmentObject private var library: ComicLibrary
    let book: ComicBook

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Group {
                if let url = library.coverURL(for: book) {
                    LocalImage(url: url, contentMode: .fill)
                } else {
                    Rectangle()
                        .fill(.secondary.opacity(0.15))
                        .overlay(Image(systemName: "book.closed"))
                }
            }
            .frame(width: 170, height: 226)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(alignment: .topTrailing) {
                if book.isFavorite {
                    Image(systemName: "star.fill")
                        .padding(8)
                        .background(.ultraThinMaterial, in: Circle())
                        .padding(7)
                }
            }
            .shadow(radius: 8, y: 4)

            Text(book.title)
                .font(.headline)
                .lineLimit(1)
                .frame(width: 170, alignment: .leading)

            Text("\(book.episodes.count) 集 · \(book.progressText)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 170, alignment: .leading)
        }
        .frame(width: 170, alignment: .leading)
    }
}

struct ImportSeriesView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var library: ComicLibrary

    @State private var title = ""
    @State private var zipFiles: [URL] = []
    @State private var episodeTitles: [String] = []
    @State private var coverFile: URL?
    @State private var coverPhotoItem: PhotosPickerItem?
    @State private var selectedCategory = "未分類"
    @State private var newCategoryName = ""
    @State private var showingNewCategoryField = false
    @State private var showingZipPicker = false
    @State private var showingCoverPicker = false
    @State private var isImporting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("作品資料") {
                    TextField("作品名稱", text: $title)

                    Picker("分類", selection: $selectedCategory) {
                        Text("＋ 建立新分類").tag("__CREATE_NEW__")
                        ForEach(library.categories, id: \.self) {
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

                    Button {
                        showingZipPicker = true
                    } label: {
                        HStack {
                            Label("選擇一個以上的 ZIP", systemImage: "doc.zipper")
                            Spacer()
                            Text(zipFiles.isEmpty ? "未選擇" : "\(zipFiles.count) 個")
                                .foregroundStyle(.secondary)
                        }
                    }

                    PhotosPicker(
                        selection: $coverPhotoItem,
                        matching: .images
                    ) {
                        HStack {
                            Label("從相簿選作品封面", systemImage: "photo")
                            Spacer()
                            Text(coverFile == nil ? "使用第一張" : "已選擇")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if !zipFiles.isEmpty {
                    Section("集數") {
                        ForEach(zipFiles.indices, id: \.self) { index in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(zipFiles[index].lastPathComponent)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                TextField(
                                    "集數名稱",
                                    text: Binding(
                                        get: { episodeTitles[index] },
                                        set: { episodeTitles[index] = $0 }
                                    )
                                )
                            }
                        }
                    }
                }

                Section {
                    Button(action: importSeries) {
                        if isImporting {
                            HStack {
                                Spacer()
                                ProgressView()
                                Text("正在匯入…")
                                Spacer()
                            }
                        } else {
                            Text("建立作品")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(
                        zipFiles.isEmpty ||
                        isImporting ||
                        (showingNewCategoryField &&
                         newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    )
                } footer: {
                    Text("一次選多個 ZIP 時，每個 ZIP 會成為一集，也可以自行修改集數名稱。")
                }
            }
            .navigationTitle("建立新作品")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .sheet(isPresented: $showingZipPicker) {
                ZipFilePicker(allowsMultipleSelection: true) { urls in
                    zipFiles = urls.sorted {
                        $0.lastPathComponent.localizedStandardCompare(
                            $1.lastPathComponent
                        ) == .orderedAscending
                    }
                    episodeTitles = zipFiles.enumerated().map {
                        library.guessedEpisodeTitle(from: $0.element, index: $0.offset)
                    }
                    if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                       let first = zipFiles.first {
                        title = library.guessedSeriesTitle(from: first)
                    }
                    showingZipPicker = false
                }
            }
            .onChange(of: coverPhotoItem) { item in
                guard let item else { return }
                Task {
                    do {
                        guard let data = try await item.loadTransferable(type: Data.self) else {
                            throw NSError(
                                domain: "CustomComic",
                                code: 11,
                                userInfo: [NSLocalizedDescriptionKey: "無法讀取封面"]
                            )
                        }
                        let tempURL = FileManager.default.temporaryDirectory
                            .appendingPathComponent("cover-\(UUID().uuidString).jpg")
                        try data.write(to: tempURL, options: .atomic)
                        coverFile = tempURL
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            }
            .alert(
                "建立失敗",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button("好", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func importSeries() {
        let category = showingNewCategoryField
            ? library.addCategory(newCategoryName)
            : selectedCategory
        isImporting = true
        do {
            try library.createSeries(
                title: title,
                category: category,
                zipURLs: zipFiles,
                episodeTitles: episodeTitles,
                coverSource: coverFile
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            isImporting = false
        }
    }
}

struct AddEpisodesView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var library: ComicLibrary
    let book: ComicBook

    @State private var zipFiles: [URL] = []
    @State private var episodeTitles: [String] = []
    @State private var showingPicker = false
    @State private var isImporting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        showingPicker = true
                    } label: {
                        HStack {
                            Label("選擇集數 ZIP", systemImage: "doc.zipper")
                            Spacer()
                            Text(zipFiles.isEmpty ? "未選擇" : "\(zipFiles.count) 個")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if !zipFiles.isEmpty {
                    Section("確認集數") {
                        ForEach(zipFiles.indices, id: \.self) { index in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(zipFiles[index].lastPathComponent)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                TextField(
                                    "集數名稱",
                                    text: Binding(
                                        get: { episodeTitles[index] },
                                        set: { episodeTitles[index] = $0 }
                                    )
                                )
                            }
                        }
                    }
                }

                Button {
                    importEpisodes()
                } label: {
                    if isImporting {
                        HStack {
                            Spacer()
                            ProgressView()
                            Text("正在加入…")
                            Spacer()
                        }
                    } else {
                        Text("加入集數")
                            .frame(maxWidth: .infinity)
                    }
                }
                .disabled(zipFiles.isEmpty || isImporting)
            }
            .navigationTitle("新增集數")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .sheet(isPresented: $showingPicker) {
                ZipFilePicker(allowsMultipleSelection: true) { urls in
                    zipFiles = urls.sorted {
                        $0.lastPathComponent.localizedStandardCompare(
                            $1.lastPathComponent
                        ) == .orderedAscending
                    }
                    episodeTitles = zipFiles.enumerated().map {
                        library.guessedEpisodeTitle(
                            from: $0.element,
                            index: book.episodes.count + $0.offset
                        )
                    }
                    showingPicker = false
                }
            }
            .alert(
                "新增失敗",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button("好", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func importEpisodes() {
        isImporting = true
        do {
            try library.addEpisodes(
                to: book.id,
                zipURLs: zipFiles,
                episodeTitles: episodeTitles
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            isImporting = false
        }
    }
}

struct SeriesDetailView: View {
    @EnvironmentObject private var library: ComicLibrary
    let bookID: UUID
    @State private var addTarget: ComicBook?

    var book: ComicBook? {
        library.book(id: bookID)
    }

    var body: some View {
        Group {
            if let book {
                List {
                    Section {
                        HStack(spacing: 16) {
                            if let url = library.coverURL(for: book) {
                                LocalImage(url: url, contentMode: .fill)
                                    .frame(width: 95, height: 125)
                                    .clipped()
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }

                            VStack(alignment: .leading, spacing: 7) {
                                Text(book.title)
                                    .font(.title2.bold())
                                Text("\(book.episodes.count) 集")
                                    .foregroundStyle(.secondary)
                                Text(book.category)
                                    .font(.caption)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 4)
                                    .background(.secondary.opacity(0.14), in: Capsule())
                            }
                        }
                        .padding(.vertical, 8)
                    }

                    Section("集數") {
                        ForEach(book.episodes) { episode in
                            NavigationLink {
                                ReaderEntryView(
                                    bookID: book.id,
                                    episodeID: episode.id
                                )
                            } label: {
                                EpisodeRow(episode: episode)
                            }
                            .contextMenu {
                                Button(role: .destructive) {
                                    library.deleteEpisode(
                                        bookID: book.id,
                                        episodeID: episode.id
                                    )
                                } label: {
                                    Label("刪除本集", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
                .navigationTitle(book.title)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            addTarget = book
                        } label: {
                            Label("新增集數", systemImage: "plus")
                        }
                    }
                }
                .sheet(item: $addTarget) {
                    AddEpisodesView(book: $0)
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                    Text("找不到作品")
                        .font(.headline)
                }
            }
        }
    }
}

struct EpisodeRow: View {
    let episode: ComicEpisode

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(episode.title)
                Text("\(episode.pageFileNames.count) 頁")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if episode.lastPage > 0 {
                Text("\(episode.lastPage + 1)/\(episode.pageFileNames.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            } else {
                Text("未閱讀")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }
}

struct ReaderEntryView: View {
    @EnvironmentObject private var library: ComicLibrary
    let bookID: UUID
    let episodeID: UUID

    @AppStorage("resumeBehavior") private var resumeRaw = ResumeBehavior.ask.rawValue
    @State private var destinationPage: Int?
    @State private var showingResumePrompt = false

    var episode: ComicEpisode? {
        library.episode(bookID: bookID, episodeID: episodeID)
    }

    var body: some View {
        Group {
            if episode != nil, let destinationPage {
                ReaderView(
                    bookID: bookID,
                    episodeID: episodeID,
                    initialPage: destinationPage
                )
            } else {
                ProgressView()
                    .onAppear(perform: decideResume)
            }
        }
        .confirmationDialog(
            "上次看到第 \((episode?.lastPage ?? 0) + 1) 頁",
            isPresented: $showingResumePrompt,
            titleVisibility: .visible
        ) {
            Button("繼續閱讀") {
                destinationPage = episode?.lastPage ?? 0
            }
            Button("從頭開始") {
                destinationPage = 0
            }
            Button("取消", role: .cancel) {}
        }
    }

    private func decideResume() {
        guard let episode else { return }
        let behavior = ResumeBehavior(rawValue: resumeRaw) ?? .ask
        if episode.lastPage <= 0 {
            destinationPage = 0
        } else {
            switch behavior {
            case .ask:
                showingResumePrompt = true
            case .alwaysResume:
                destinationPage = episode.lastPage
            case .alwaysStartOver:
                destinationPage = 0
            }
        }
    }
}

struct ReaderView: View {
    @EnvironmentObject private var library: ComicLibrary
    let bookID: UUID
    let episodeID: UUID
    let initialPage: Int

    @AppStorage("readingMode") private var modeRaw = ReadingMode.vertical.rawValue
    @AppStorage("resumeBehavior") private var resumeRaw = ResumeBehavior.ask.rawValue
    @State private var page: Int
    @State private var controlsVisible = true
    @State private var showingSettings = false
    @State private var showingJump = false
    @State private var jumpText = ""

    init(bookID: UUID, episodeID: UUID, initialPage: Int) {
        self.bookID = bookID
        self.episodeID = episodeID
        self.initialPage = initialPage
        _page = State(initialValue: initialPage)
    }

    private var episode: ComicEpisode? {
        library.episode(bookID: bookID, episodeID: episodeID)
    }

    private var urls: [URL] {
        episode.map(library.pageURLs(for:)) ?? []
    }

    private var mode: ReadingMode {
        ReadingMode(rawValue: modeRaw) ?? .vertical
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if !urls.isEmpty {
                if mode == .vertical {
                    ContinuousZoomReader(
                        urls: urls,
                        initialPage: initialPage
                    ) { newPage in
                        page = newPage
                    }
                    .ignoresSafeArea()
                } else {
                    ZStack {
                        ZoomableImagePage(url: urls[page])
                            .ignoresSafeArea()

                        HStack(spacing: 0) {
                            Color.clear
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    if page > 0 { page -= 1 }
                                }
                            Color.clear
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    if page < urls.count - 1 { page += 1 }
                                }
                        }
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .simultaneousGesture(
            TapGesture().onEnded {
                controlsVisible.toggle()
            }
        )
        .toolbar(controlsVisible ? .visible : .hidden, for: .navigationBar)
        .toolbar(controlsVisible ? .visible : .hidden, for: .bottomBar)
        .navigationTitle(episode?.title ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    showingJump = true
                } label: {
                    Image(systemName: "number")
                }

                Button {
                    showingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
            }

            ToolbarItem(placement: .bottomBar) {
                VStack(spacing: 2) {
                    Slider(
                        value: Binding(
                            get: { Double(page) },
                            set: { page = Int($0.rounded()) }
                        ),
                        in: 0...Double(max(0, urls.count - 1)),
                        step: 1
                    )
                    Text("\(page + 1) / \(urls.count)")
                        .font(.caption.monospacedDigit())
                }
            }
        }
        .onChange(of: page) { newPage in
            library.updateLastPage(
                bookID: bookID,
                episodeID: episodeID,
                page: newPage
            )
        }
        .sheet(isPresented: $showingSettings) {
            ReaderSettingsView()
        }
        .alert("跳轉頁面", isPresented: $showingJump) {
            TextField("頁碼", text: $jumpText)
                .keyboardType(.numberPad)
            Button("跳轉") {
                if let number = Int(jumpText) {
                    page = min(max(number - 1, 0), max(0, urls.count - 1))
                }
                jumpText = ""
            }
            Button("取消", role: .cancel) {
                jumpText = ""
            }
        } message: {
            Text("輸入 1 到 \(urls.count)")
        }
    }
}

struct ReaderSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("readingMode") private var modeRaw = ReadingMode.vertical.rawValue
    @AppStorage("resumeBehavior") private var resumeRaw = ResumeBehavior.ask.rawValue

    var body: some View {
        NavigationStack {
            Form {
                Section("閱讀模式") {
                    Picker("模式", selection: $modeRaw) {
                        ForEach(ReadingMode.allCases) { mode in
                            Text(mode.title).tag(mode.rawValue)
                        }
                    }
                    .pickerStyle(.inline)
                }

                Section("開啟閱讀紀錄") {
                    Picker("上次閱讀位置", selection: $resumeRaw) {
                        ForEach(ResumeBehavior.allCases) { behavior in
                            Text(behavior.title).tag(behavior.rawValue)
                        }
                    }
                    .pickerStyle(.inline)
                }

                Section {
                    Text("單頁模式與捲軸模式都支援雙指縮放。捲軸模式放大後不會因為上下滑動突然恢復大小。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("閱讀設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}

struct HiddenLibraryView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var library: ComicLibrary
    @StateObject private var auth = BiometricAuth()

    @State private var didRequestAuthentication = false
    @State private var searchText = ""
    @State private var addEpisodeTarget: ComicBook?

    private let columns = [
        GridItem(.adaptive(minimum: 145, maximum: 190), spacing: 18)
    ]

    private var filteredHiddenBooks: [ComicBook] {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return library.hiddenBooks
        }

        return library.hiddenBooks.filter { book in
            book.title.localizedCaseInsensitiveContains(searchText) ||
            book.category.localizedCaseInsensitiveContains(searchText) ||
            book.episodes.contains {
                $0.title.localizedCaseInsensitiveContains(searchText)
            }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if auth.isUnlocked {
                    hiddenLibraryContent
                } else {
                    lockedContent
                }
            }
            .navigationTitle("隱藏漫畫")
            .navigationBarTitleDisplayMode(.large)
            .searchable(
                text: $searchText,
                isPresented: .constant(auth.isUnlocked),
                prompt: "搜尋隱藏作品、分類或集數"
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("關閉") { dismiss() }
                }
            }
            .task {
                guard !didRequestAuthentication else { return }
                didRequestAuthentication = true
                auth.authenticate()
            }
            .sheet(item: $addEpisodeTarget) { book in
                AddEpisodesView(book: book)
            }
            .alert(
                "驗證失敗",
                isPresented: Binding(
                    get: { auth.errorMessage != nil },
                    set: { if !$0 { auth.errorMessage = nil } }
                )
            ) {
                Button("重試") {
                    auth.authenticate()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text(auth.errorMessage ?? "")
            }
        }
    }

    @ViewBuilder
    private var hiddenLibraryContent: some View {
        if filteredHiddenBooks.isEmpty {
            VStack(spacing: 14) {
                Image(systemName: "eye.slash")
                    .font(.system(size: 52))
                    .foregroundStyle(.secondary)

                Text(searchText.isEmpty ? "沒有隱藏漫畫" : "找不到符合的作品")
                    .font(.title2.bold())
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVGrid(
                    columns: columns,
                    alignment: .leading,
                    spacing: 22
                ) {
                    ForEach(filteredHiddenBooks) { book in
                        NavigationLink {
                            SeriesDetailView(bookID: book.id)
                        } label: {
                            BookCard(book: book)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button {
                                addEpisodeTarget = book
                            } label: {
                                Label(
                                    "新增集數",
                                    systemImage: "plus.rectangle.on.rectangle"
                                )
                            }

                            Button {
                                library.toggleFavorite(book)
                            } label: {
                                Label(
                                    book.isFavorite ? "取消收藏" : "加入收藏",
                                    systemImage: book.isFavorite
                                        ? "star.slash"
                                        : "star"
                                )
                            }

                            Button {
                                library.setHidden(false, for: book)
                            } label: {
                                Label("取消隱藏", systemImage: "eye")
                            }

                            Button(role: .destructive) {
                                library.delete(book)
                            } label: {
                                Label("刪除作品", systemImage: "trash")
                            }
                        }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var lockedContent: some View {
        VStack(spacing: 18) {
            Image(systemName: "lock.fill")
                .font(.system(size: 52))
                .foregroundStyle(.secondary)

            Text("隱藏書庫已鎖定")
                .font(.title2.bold())

            Button("使用 \(auth.displayName) 解鎖") {
                auth.authenticate()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
