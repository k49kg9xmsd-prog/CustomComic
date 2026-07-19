import SwiftUI

@MainActor
final class PlayerSettings: ObservableObject {
    static let shared = PlayerSettings()
    private let defaults = UserDefaults.standard

    enum SpeedMemoryMode: String, CaseIterable, Identifiable {
        case none, global, perVideo
        var id: String { rawValue }
        var title: String {
            switch self {
            case .none: return "不記住"
            case .global: return "全部影片共用"
            case .perVideo: return "每部影片分開"
            }
        }
    }

    @Published var defaultSpeed: Double { didSet { save("player.defaultSpeed", defaultSpeed) } }
    @Published var speedMemoryRaw: String { didSet { save("player.speedMemory", speedMemoryRaw) } }

    @Published var gesturesEnabled: Bool { didSet { save("player.gestures.enabled", gesturesEnabled) } }
    @Published var singleTapEnabled: Bool { didSet { save("player.gestures.singleTap", singleTapEnabled) } }
    @Published var centerDoubleTapEnabled: Bool { didSet { save("player.gestures.centerDouble", centerDoubleTapEnabled) } }
    @Published var brightnessGestureEnabled: Bool { didSet { save("player.gestures.brightness", brightnessGestureEnabled) } }
    @Published var volumeGestureEnabled: Bool { didSet { save("player.gestures.volume", volumeGestureEnabled) } }
    @Published var seekGestureEnabled: Bool { didSet { save("player.gestures.seek", seekGestureEnabled) } }
    @Published var longPressSpeedEnabled: Bool { didSet { save("player.gestures.longPress", longPressSpeedEnabled) } }

    @Published var playButtonHex: String { didSet { save("player.color.play", playButtonHex) } }
    @Published var playedTrackHex: String { didSet { save("player.color.played", playedTrackHex) } }
    @Published var unplayedTrackHex: String { didSet { save("player.color.unplayed", unplayedTrackHex) } }
    @Published var thumbHex: String { didSet { save("player.color.thumb", thumbHex) } }
    @Published var textHex: String { didSet { save("player.color.text", textHex) } }
    @Published var topBarHex: String { didSet { save("player.color.topBar", topBarHex) } }
    @Published var bottomBarHex: String { didSet { save("player.color.bottomBar", bottomBarHex) } }
    @Published var hudBackgroundHex: String { didSet { save("player.color.hudBackground", hudBackgroundHex) } }
    @Published var hudTextHex: String { didSet { save("player.color.hudText", hudTextHex) } }
    @Published var restartHex: String { didSet { save("player.color.restart", restartHex) } }

    @Published var topBarOpacity: Double { didSet { save("player.opacity.top", topBarOpacity) } }
    @Published var bottomBarOpacity: Double { didSet { save("player.opacity.bottom", bottomBarOpacity) } }
    @Published var hudOpacity: Double { didSet { save("player.opacity.hud", hudOpacity) } }
    @Published var buttonOpacity: Double { didSet { save("player.opacity.button", buttonOpacity) } }

    var speedMemoryMode: SpeedMemoryMode {
        get { SpeedMemoryMode(rawValue: speedMemoryRaw) ?? .global }
        set { speedMemoryRaw = newValue.rawValue }
    }

    private init() {
        defaultSpeed = defaults.object(forKey: "player.defaultSpeed") as? Double ?? 1.0
        speedMemoryRaw = defaults.string(forKey: "player.speedMemory") ?? SpeedMemoryMode.global.rawValue
        gesturesEnabled = defaults.object(forKey: "player.gestures.enabled") as? Bool ?? true
        singleTapEnabled = defaults.object(forKey: "player.gestures.singleTap") as? Bool ?? true
        centerDoubleTapEnabled = defaults.object(forKey: "player.gestures.centerDouble") as? Bool ?? true
        brightnessGestureEnabled = defaults.object(forKey: "player.gestures.brightness") as? Bool ?? true
        volumeGestureEnabled = defaults.object(forKey: "player.gestures.volume") as? Bool ?? true
        seekGestureEnabled = defaults.object(forKey: "player.gestures.seek") as? Bool ?? true
        longPressSpeedEnabled = defaults.object(forKey: "player.gestures.longPress") as? Bool ?? true

        playButtonHex = defaults.string(forKey: "player.color.play") ?? "FFFFFF"
        playedTrackHex = defaults.string(forKey: "player.color.played") ?? "FFFFFF"
        unplayedTrackHex = defaults.string(forKey: "player.color.unplayed") ?? "7A7A7A"
        thumbHex = defaults.string(forKey: "player.color.thumb") ?? "FFFFFF"
        textHex = defaults.string(forKey: "player.color.text") ?? "FFFFFF"
        topBarHex = defaults.string(forKey: "player.color.topBar") ?? "000000"
        bottomBarHex = defaults.string(forKey: "player.color.bottomBar") ?? "000000"
        hudBackgroundHex = defaults.string(forKey: "player.color.hudBackground") ?? "000000"
        hudTextHex = defaults.string(forKey: "player.color.hudText") ?? "FFFFFF"
        restartHex = defaults.string(forKey: "player.color.restart") ?? "FFFFFF"

        topBarOpacity = defaults.object(forKey: "player.opacity.top") as? Double ?? 0.38
        bottomBarOpacity = defaults.object(forKey: "player.opacity.bottom") as? Double ?? 0.48
        hudOpacity = defaults.object(forKey: "player.opacity.hud") as? Double ?? 0.68
        buttonOpacity = defaults.object(forKey: "player.opacity.button") as? Double ?? 0.48
    }

    private func save(_ key: String, _ value: Any) { defaults.set(value, forKey: key) }

    func speed(for videoID: UUID) -> Float {
        switch speedMemoryMode {
        case .none: return Float(defaultSpeed)
        case .global:
            return Float(defaults.object(forKey: "player.lastSpeed.global") as? Double ?? defaultSpeed)
        case .perVideo:
            return Float(defaults.object(forKey: "player.lastSpeed.\(videoID.uuidString)") as? Double ?? defaultSpeed)
        }
    }

    func remember(speed: Float, for videoID: UUID) {
        switch speedMemoryMode {
        case .none: break
        case .global: defaults.set(Double(speed), forKey: "player.lastSpeed.global")
        case .perVideo: defaults.set(Double(speed), forKey: "player.lastSpeed.\(videoID.uuidString)")
        }
    }

    func setAllGestures(_ enabled: Bool) {
        gesturesEnabled = enabled
        singleTapEnabled = enabled
        centerDoubleTapEnabled = enabled
        brightnessGestureEnabled = enabled
        volumeGestureEnabled = enabled
        seekGestureEnabled = enabled
        longPressSpeedEnabled = enabled
    }

    func resetAppearance() {
        playButtonHex = "FFFFFF"; playedTrackHex = "FFFFFF"; unplayedTrackHex = "7A7A7A"
        thumbHex = "FFFFFF"; textHex = "FFFFFF"; topBarHex = "000000"; bottomBarHex = "000000"
        hudBackgroundHex = "000000"; hudTextHex = "FFFFFF"; restartHex = "FFFFFF"
        topBarOpacity = 0.38; bottomBarOpacity = 0.48; hudOpacity = 0.68; buttonOpacity = 0.48
    }

    func resetAll() {
        defaultSpeed = 1.0
        speedMemoryMode = .global
        setAllGestures(true)
        resetAppearance()
    }
}

struct PlayerSettingsView: View {
    @EnvironmentObject private var settings: PlayerSettings
    @State private var resetAppearanceAlert = false
    @State private var resetAllAlert = false

    private let speeds: [Double] = [0.5, 0.75, 1, 1.25, 1.5, 2]

    var body: some View {
        Form {
            Section("播放速度") {
                Picker("預設倍速", selection: $settings.defaultSpeed) {
                    ForEach(speeds, id: \.self) { Text(speedText($0)).tag($0) }
                }
                Picker("倍速記憶", selection: Binding(
                    get: { settings.speedMemoryMode },
                    set: { settings.speedMemoryMode = $0 }
                )) {
                    ForEach(PlayerSettings.SpeedMemoryMode.allCases) { Text($0.title).tag($0) }
                }
            }

            Section("播放器手勢") {
                Toggle("啟用播放器手勢", isOn: $settings.gesturesEnabled)
                Group {
                    Toggle("單擊顯示／隱藏控制列", isOn: $settings.singleTapEnabled)
                    Toggle("雙擊中央播放／暫停", isOn: $settings.centerDoubleTapEnabled)
                    Toggle("左側上下滑調亮度", isOn: $settings.brightnessGestureEnabled)
                    Toggle("右側上下滑調影片音量", isOn: $settings.volumeGestureEnabled)
                    Toggle("左右滑拖曳進度", isOn: $settings.seekGestureEnabled)
                    Toggle("長按臨時 2 倍速", isOn: $settings.longPressSpeedEnabled)
                }
                .disabled(!settings.gesturesEnabled)

                HStack {
                    Button("全部開啟") { settings.setAllGestures(true) }
                    Spacer()
                    Button("全部關閉", role: .destructive) { settings.setAllGestures(false) }
                }
            }

            Section("播放器 UI 顏色") {
                colorRow("播放／暫停鍵", keyPath: \.playButtonHex)
                colorRow("已播放進度", keyPath: \.playedTrackHex)
                colorRow("未播放進度", keyPath: \.unplayedTrackHex)
                colorRow("進度圓點", keyPath: \.thumbHex)
                colorRow("控制列文字", keyPath: \.textHex)
                colorRow("頂部控制列", keyPath: \.topBarHex)
                colorRow("底部控制列", keyPath: \.bottomBarHex)
                colorRow("HUD 背景", keyPath: \.hudBackgroundHex)
                colorRow("HUD 圖示與文字", keyPath: \.hudTextHex)
                colorRow("從頭播放提示", keyPath: \.restartHex)
            }

            Section("透明度") {
                opacityRow("頂部控制列", value: $settings.topBarOpacity)
                opacityRow("底部控制列", value: $settings.bottomBarOpacity)
                opacityRow("HUD 背景", value: $settings.hudOpacity)
                opacityRow("按鈕背景", value: $settings.buttonOpacity)
            }

            Section("預覽") {
                PlayerThemePreview()
            }

            Section("重設") {
                Button("恢復播放器預設外觀", role: .destructive) { resetAppearanceAlert = true }
                Button("恢復全部播放器設定", role: .destructive) { resetAllAlert = true }
            }
        }
        .navigationTitle("播放設定")
        .navigationBarTitleDisplayMode(.inline)
        .alert("恢復預設外觀？", isPresented: $resetAppearanceAlert) {
            Button("取消", role: .cancel) {}
            Button("恢復", role: .destructive) { settings.resetAppearance() }
        } message: { Text("只會重設播放器顏色與透明度，不會刪除影片或觀看進度。") }
        .alert("恢復全部播放器設定？", isPresented: $resetAllAlert) {
            Button("取消", role: .cancel) {}
            Button("全部恢復", role: .destructive) { settings.resetAll() }
        } message: { Text("倍速、手勢和播放器外觀都會恢復預設值。") }
    }

    private func colorRow(_ title: String, keyPath: ReferenceWritableKeyPath<PlayerSettings, String>) -> some View {
        ColorPicker(title, selection: Binding(
            get: { Color(hex: settings[keyPath: keyPath]) },
            set: { if let hex = $0.hexString() { settings[keyPath: keyPath] = hex } }
        ), supportsOpacity: false)
    }

    private func opacityRow(_ title: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(title)  \(Int(value.wrappedValue * 100))%")
            Slider(value: value, in: 0.05...1)
        }
    }

    private func speedText(_ value: Double) -> String { value == 1 ? "1x" : String(format: "%gx", value) }
}

private struct PlayerThemePreview: View {
    @EnvironmentObject private var settings: PlayerSettings
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18).fill(Color.black)
            VStack {
                HStack { Image(systemName: "xmark"); Text("動畫標題"); Spacer(); Text("1x") }
                    .padding(10)
                    .foregroundStyle(Color(hex: settings.textHex))
                    .background(Color(hex: settings.topBarHex).opacity(settings.topBarOpacity))
                Spacer()
                Image(systemName: "pause.fill")
                    .font(.title)
                    .foregroundStyle(Color(hex: settings.playButtonHex))
                    .padding(18)
                    .background(Color.black.opacity(settings.buttonOpacity), in: Circle())
                Spacer()
                HStack(spacing: 0) {
                    Capsule().fill(Color(hex: settings.playedTrackHex)).frame(width: 100, height: 4)
                    Capsule().fill(Color(hex: settings.unplayedTrackHex)).frame(height: 4)
                }
                .padding(12)
                .background(Color(hex: settings.bottomBarHex).opacity(settings.bottomBarOpacity))
            }
        }
        .frame(height: 180)
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}
