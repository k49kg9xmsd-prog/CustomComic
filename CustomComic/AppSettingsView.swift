import SwiftUI
import PhotosUI

struct AppSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appearance: AppearanceManager

    @State private var imageItem: PhotosPickerItem?
    @State private var videoItem: PhotosPickerItem?
    @State private var isLoadingMedia = false
    @State private var showingImageSource = false
    @State private var showingVideoSource = false
    @State private var showingImageFilePicker = false
    @State private var showingVideoFilePicker = false
    @State private var showingImagePhotoPicker = false
    @State private var showingVideoPhotoPicker = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("背景類型") {
                    Picker(
                        "背景",
                        selection: $appearance.backgroundStyleRaw
                    ) {
                        ForEach(AppBackgroundStyle.allCases) { style in
                            Text(style.title).tag(style.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if appearance.style == .solid {
                    Section("背景顏色") {
                        ColorPicker(
                            "調色盤",
                            selection: Binding(
                                get: {
                                    Color(hex: appearance.backgroundHex)
                                },
                                set: { newColor in
                                    if let hex = newColor.hexString() {
                                        appearance.backgroundHex = hex
                                    }
                                }
                            ),
                            supportsOpacity: false
                        )

                        HStack {
                            Text("色碼")
                            Spacer()
                            Text(appearance.backgroundHex.uppercased())
                                .font(.body.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if appearance.style == .image {
                    Section("背景圖片") {
                        Button {
                            showingImageSource = true
                        } label: {
                            Label("選擇背景圖片", systemImage: "photo")
                        }
                    }
                }

                if appearance.style == .video {
                    Section("背景影片") {
                        Button {
                            showingVideoSource = true
                        } label: {
                            Label("選擇背景影片", systemImage: "video")
                        }

                        VStack(alignment: .leading) {
                            Text(
                                "音量 \(Int(appearance.backgroundVideoVolume * 100))%"
                            )

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
                            Text(
                                "背景可見度 \(Int(appearance.backgroundOpacity * 100))%"
                            )

                            Slider(
                                value: $appearance.backgroundOpacity,
                                in: 0...1
                            )
                        }

                        VStack(alignment: .leading) {
                            Text(
                                "模糊 \(Int(appearance.backgroundBlur))"
                            )

                            Slider(
                                value: $appearance.backgroundBlur,
                                in: 0...30
                            )
                        }
                    }
                }

                if isLoadingMedia {
                    Section {
                        HStack {
                            ProgressView()
                            Text("正在處理相簿內容…")
                        }
                    }
                }

                Section {
                    Text(
                        "背景影片會循環播放；音量大於 0 時會解除靜音。部分影片本身可能沒有音軌。"
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("背景設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
            .confirmationDialog("選擇圖片來源", isPresented: $showingImageSource, titleVisibility: .visible) {
                Button("檔案") { showingImageFilePicker = true }
                Button("相簿") { showingImagePhotoPicker = true }
                Button("取消", role: .cancel) {}
            }
            .confirmationDialog("選擇影片來源", isPresented: $showingVideoSource, titleVisibility: .visible) {
                Button("檔案") { showingVideoFilePicker = true }
                Button("相簿") { showingVideoPhotoPicker = true }
                Button("取消", role: .cancel) {}
            }
            .sheet(isPresented: $showingImageFilePicker) {
                ImageFilePicker { url in
                    showingImageFilePicker = false
                    do { try appearance.saveBackgroundImage(Data(contentsOf: url)) }
                    catch { errorMessage = error.localizedDescription }
                }
            }
            .sheet(isPresented: $showingVideoFilePicker) {
                VideoFilePicker { urls in
                    showingVideoFilePicker = false
                    guard let url = urls.first else { return }
                    do { try appearance.saveBackgroundVideoData(Data(contentsOf: url)) }
                    catch { errorMessage = error.localizedDescription }
                }
            }
            .photosPicker(isPresented: $showingImagePhotoPicker, selection: $imageItem, matching: .images)
            .photosPicker(isPresented: $showingVideoPhotoPicker, selection: $videoItem, matching: .videos)
            .onChange(of: imageItem) { item in
                loadImage(item)
            }
            .onChange(of: videoItem) { item in
                loadVideo(item)
            }
            .alert(
                "設定失敗",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: {
                        if !$0 {
                            errorMessage = nil
                        }
                    }
                )
            ) {
                Button("好", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func loadImage(_ item: PhotosPickerItem?) {
        guard let item else { return }

        isLoadingMedia = true

        Task {
            do {
                guard let data = try await item.loadTransferable(
                    type: Data.self
                ) else {
                    throw NSError(
                        domain: "CustomComic",
                        code: 1,
                        userInfo: [
                            NSLocalizedDescriptionKey: "無法讀取背景圖片"
                        ]
                    )
                }

                try await MainActor.run {
                    try appearance.saveBackgroundImage(data)
                    isLoadingMedia = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoadingMedia = false
                }
            }
        }
    }

    private func loadVideo(_ item: PhotosPickerItem?) {
        guard let item else { return }

        isLoadingMedia = true

        Task {
            do {
                guard let data = try await item.loadTransferable(
                    type: Data.self
                ) else {
                    throw NSError(
                        domain: "CustomComic",
                        code: 2,
                        userInfo: [
                            NSLocalizedDescriptionKey: "無法讀取背景影片"
                        ]
                    )
                }

                try await MainActor.run {
                    try appearance.saveBackgroundVideoData(data)
                    isLoadingMedia = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoadingMedia = false
                }
            }
        }
    }
}
