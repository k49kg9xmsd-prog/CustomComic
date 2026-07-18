import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var library: ComicLibrary
    @State private var showingImport = false
    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 18)]

    var body: some View {
        NavigationStack {
            Group {
                if library.books.isEmpty {
                    VStack(spacing: 14) {
                        Image(systemName: "books.vertical")
                            .font(.system(size: 54))
                            .foregroundStyle(.secondary)

                        Text("還沒有內容")
                            .font(.title2.bold())

                        Text("按右上角新增，選擇含有圖片的資料夾。")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(32)
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 22) {
                            ForEach(library.books) { book in
                                NavigationLink {
                                    ReaderView(book: book)
                                } label: {
                                    BookCard(book: book)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button(role: .destructive) {
                                        library.delete(book)
                                    } label: {
                                        Label("刪除", systemImage: "trash")
                                    }
                                }
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("自訂漫畫庫")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingImport = true } label: {
                        Label("新增", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingImport) {
                ImportBookView()
            }
        }
    }
}

struct BookCard: View {
    @EnvironmentObject private var library: ComicLibrary
    let book: ComicBook

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            LocalImage(url: library.coverURL(for: book), contentMode: .fill)
                .frame(maxWidth: .infinity)
                .aspectRatio(3/4, contentMode: .fit)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .shadow(radius: 8, y: 4)

            Text(book.title).font(.headline).lineLimit(1)
            Text("\(book.pageFileNames.count) 張圖片")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct ImportBookView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var library: ComicLibrary

    @State private var title = ""
    @State private var imageFiles: [URL] = []
    @State private var coverFile: URL?
    @State private var showingFolderPicker = false
    @State private var showingCoverPicker = false
    @State private var isImporting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("作品資料") {
                    TextField("作品名稱", text: $title)

                    Button { showingFolderPicker = true } label: {
                        HStack {
                            Label("選擇圖片資料夾", systemImage: "folder")
                            Spacer()
                            Text(imageFiles.isEmpty ? "未選擇" : "\(imageFiles.count) 張")
                                .foregroundStyle(.secondary)
                        }
                    }

                    Button { showingCoverPicker = true } label: {
                        HStack {
                            Label("自訂封面", systemImage: "photo")
                            Spacer()
                            Text(coverFile == nil ? "使用第一張" : "已選擇")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    Button(action: importBook) {
                        if isImporting {
                            ProgressView().frame(maxWidth: .infinity)
                        } else {
                            Text("建立作品").frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(imageFiles.isEmpty || isImporting)
                } footer: {
                    Text("圖片會複製到 App 裡，之後完全不需要網路。")
                }
            }
            .navigationTitle("建立新作品")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .sheet(isPresented: $showingFolderPicker) {
                FolderPicker { urls in
                    imageFiles = urls.sorted {
                        $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
                    }
                    showingFolderPicker = false
                }
            }
            .sheet(isPresented: $showingCoverPicker) {
                ImageFilePicker { url in
                    coverFile = url
                    showingCoverPicker = false
                }
            }
            .alert("建立失敗", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("好", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func importBook() {
        isImporting = true
        do {
            try library.addBook(title: title, sourceFiles: imageFiles, coverSource: coverFile)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            isImporting = false
        }
    }
}

struct ReaderView: View {
    @EnvironmentObject private var library: ComicLibrary
    let book: ComicBook

    @AppStorage("readingMode") private var readingModeRaw = ReadingMode.vertical.rawValue
    @State private var page = 0
    @State private var showingSettings = false
    @State private var controlsVisible = true

    private var mode: ReadingMode {
        ReadingMode(rawValue: readingModeRaw) ?? .vertical
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if mode == .vertical {
                VerticalReader(pageURLs: library.pageURLs(for: book))
            } else {
                PagedReader(
                    urls: library.pageURLs(for: book),
                    page: $page,
                    controlsVisible: $controlsVisible
                )
            }
        }
        .toolbar(controlsVisible ? .visible : .hidden, for: .navigationBar)
        .navigationTitle(book.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingSettings = true } label: {
                    Image(systemName: "gearshape")
                }
            }
            ToolbarItem(placement: .bottomBar) {
                if mode == .paged {
                    Text("\(page + 1) / \(book.pageFileNames.count)")
                        .font(.caption.monospacedDigit())
                }
            }
        }
        .onAppear {
            page = min(book.lastPage, max(0, book.pageFileNames.count - 1))
        }
        .onChange(of: page) { newPage in
            library.updateLastPage(bookID: book.id, page: newPage)
        }
        .sheet(isPresented: $showingSettings) {
            NavigationStack {
                List(ReadingMode.allCases) { option in
                    Button {
                        readingModeRaw = option.rawValue
                        showingSettings = false
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(option.title).foregroundStyle(.primary)
                                Text(option.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if mode == option { Image(systemName: "checkmark") }
                        }
                    }
                }
                .navigationTitle("閱讀設定")
                .navigationBarTitleDisplayMode(.inline)
            }
            .presentationDetents([.medium])
        }
    }
}

struct VerticalReader: View {
    let pageURLs: [URL]

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(pageURLs.enumerated()), id: \.offset) { _, url in
                    LocalImage(url: url, contentMode: .fit)
                }
            }
        }
        .background(.black)
    }
}

struct PagedReader: View {
    let urls: [URL]
    @Binding var page: Int
    @Binding var controlsVisible: Bool

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if urls.indices.contains(page) {
                    LocalImage(url: urls[page], contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

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

                Color.clear
                    .frame(width: proxy.size.width * 0.2)
                    .contentShape(Rectangle())
                    .onTapGesture { controlsVisible.toggle() }
            }
        }
    }
}
