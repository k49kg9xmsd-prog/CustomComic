import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct AppSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appearance: AppearanceManager

    @State private var imageItem: PhotosPickerItem?
    @State private var videoItem: PhotosPickerItem?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("背景類型") {
                    Picker("背景", selection: $appearance.backgroundStyleRaw) {
                        ForEach(AppBackgroundStyle.allCases) { style in
                            Text(style.title).tag(style.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if appearance.style == .solid {
                    Section("背景顏色") {
                        TextField("#000000", text: $appearance.backgroundHex)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                    }
                }

                if appearance.style == .image {
                    Section("背景圖片") {
                        PhotosPicker(
                            selection: $imageItem,
                            matching: .images
                        ) {
                            Label("從相簿選圖片", systemImage: "photo")
                        }
                    }
                }

                if appearance.style == .video {
                    Section("背景影片") {
                        PhotosPicker(
                            selection: $videoItem,
                            matching: .videos
                        ) {
                            Label("從相簿選影片", systemImage: "video")
                        }

                        VStack(alignment: .leading) {
                            Text("音量 \(Int(appearance.backgroundVideoVolume * 100))%")
                            Slider(
                                value: $appearance.backgroundVideoVolume,
                                in: 0...1
                            )
                        }
                    }
                }

                if appearance.style != .solid {
                    Section("顯示效果") {
                        VStack(alignment: .leading) {
                            Text("透明度 \(Int(appearance.backgroundOpacity * 100))%")
                            Slider(
                                value: $appearance.backgroundOpacity,
                                in: 0...1
                            )
                        }

                        VStack(alignment: .leading) {
                            Text("模糊 \(Int(appearance.backgroundBlur))")
                            Slider(
                                value: $appearance.backgroundBlur,
                                in: 0...30
                            )
                        }
                    }
                }

                Section {
                    Text("背景影片會循環播放。預設靜音，避免開啟 App 時突然發出聲音。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .onChange(of: imageItem) { item in
                guard let item else { return }
                Task {
                    do {
                        guard let data = try await item.loadTransferable(type: Data.self) else {
                            throw NSError(
                                domain: "CustomComic",
                                code: 1,
                                userInfo: [NSLocalizedDescriptionKey: "無法讀取圖片"]
                            )
                        }
                        try appearance.saveBackgroundImage(data)
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            }

            .onChange(of: videoItem) { item in
                guard let item else { return }

                Task {
                    do {
                        guard let movie = try await item.loadTransferable(
                            type: MovieTransferable.self
                        ) else {
                            throw NSError(
                                domain: "CustomComic",
                                code: 20,
                                userInfo: [
                                    NSLocalizedDescriptionKey: "無法從相簿讀取影片"
                                ]
                            )
                        }

                        try appearance.saveBackgroundVideo(from: movie.url)
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            }
            .alert(
                "設定失敗",
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
}


struct MovieTransferable: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let target = FileManager.default.temporaryDirectory
                .appendingPathComponent(
                    "background-\(UUID().uuidString).\(received.file.pathExtension)"
                )

            if FileManager.default.fileExists(atPath: target.path) {
                try FileManager.default.removeItem(at: target)
            }

            try FileManager.default.copyItem(
                at: received.file,
                to: target
            )
            return MovieTransferable(url: target)
        }
    }
}
