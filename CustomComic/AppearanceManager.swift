import SwiftUI
import AVKit

@MainActor
final class AppearanceManager: ObservableObject {
    @Published var isReaderActive = false
    @Published private(set) var backgroundRevision = 0
    @Published var backgroundStyleRaw: String {
        didSet { defaults.set(backgroundStyleRaw, forKey: Keys.style) }
    }

    @Published var backgroundHex: String {
        didSet { defaults.set(backgroundHex, forKey: Keys.hex) }
    }

    @Published var backgroundOpacity: Double {
        didSet { defaults.set(backgroundOpacity, forKey: Keys.opacity) }
    }

    @Published var backgroundVideoVolume: Double {
        didSet { defaults.set(backgroundVideoVolume, forKey: Keys.volume) }
    }

    @Published var backgroundBlur: Double {
        didSet { defaults.set(backgroundBlur, forKey: Keys.blur) }
    }

    let imageURL: URL
    let videoURL: URL

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let style = "backgroundStyle"
        static let hex = "backgroundHex"
        static let opacity = "backgroundOpacity"
        static let volume = "backgroundVideoVolume"
        static let blur = "backgroundBlur"
    }

    init() {
        let documents = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        )[0]

        imageURL = documents.appendingPathComponent("custom-background-image.jpg")
        videoURL = documents.appendingPathComponent("custom-background-video.mov")

        backgroundStyleRaw = defaults.string(forKey: Keys.style)
            ?? AppBackgroundStyle.solid.rawValue
        backgroundHex = defaults.string(forKey: Keys.hex) ?? "#000000"

        if defaults.object(forKey: Keys.opacity) == nil {
            backgroundOpacity = 1.0
        } else {
            backgroundOpacity = defaults.double(forKey: Keys.opacity)
        }

        if defaults.object(forKey: Keys.volume) == nil {
            backgroundVideoVolume = 0
        } else {
            backgroundVideoVolume = defaults.double(forKey: Keys.volume)
        }

        if defaults.object(forKey: Keys.blur) == nil {
            backgroundBlur = 0
        } else {
            backgroundBlur = defaults.double(forKey: Keys.blur)
        }
    }

    var style: AppBackgroundStyle {
        AppBackgroundStyle(rawValue: backgroundStyleRaw) ?? .solid
    }

    func saveBackgroundImage(_ data: Data) throws {
        try data.write(to: imageURL, options: .atomic)
        backgroundRevision &+= 1
    }

    func saveBackgroundVideoData(_ data: Data) throws {
        try data.write(to: videoURL, options: .atomic)
        backgroundRevision &+= 1
    }

    func beginReading() {
        isReaderActive = true
    }

    func endReading() {
        isReaderActive = false
    }
}

struct AppBackgroundView: View {
    @EnvironmentObject private var appearance: AppearanceManager

    var body: some View {
        ZStack {
            Color(hex: appearance.backgroundHex)
                .ignoresSafeArea()

            switch appearance.style {
            case .solid:
                EmptyView()

            case .image:
                if let image = UIImage(contentsOfFile: appearance.imageURL.path) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .id(appearance.backgroundRevision)
                        .ignoresSafeArea()
                        .blur(radius: appearance.backgroundBlur)
                        .opacity(appearance.backgroundOpacity)
                        .allowsHitTesting(false)
                }

            case .video:
                if !appearance.isReaderActive,
                   FileManager.default.fileExists(
                    atPath: appearance.videoURL.path
                   ) {
                    LoopingVideoView(
                        url: appearance.videoURL,
                        volume: Float(appearance.backgroundVideoVolume)
                    )
                    .id(appearance.backgroundRevision)
                    .ignoresSafeArea()
                    .blur(radius: appearance.backgroundBlur)
                    .opacity(appearance.backgroundOpacity)
                    .allowsHitTesting(false)
                }
            }
        }
    }
}

struct LoopingVideoView: UIViewRepresentable {
    let url: URL
    let volume: Float

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> PlayerUIView {
        let view = PlayerUIView()
        context.coordinator.attach(to: view.player)

        let item = AVPlayerItem(url: url)
        context.coordinator.looper = AVPlayerLooper(
            player: view.player,
            templateItem: item
        )

        configureAudio(for: volume)
        applyVolume(to: view.player)
        view.player.play()
        return view
    }

    func updateUIView(_ view: PlayerUIView, context: Context) {
        context.coordinator.attach(to: view.player)
        configureAudio(for: volume)
        applyVolume(to: view.player)

        if view.player.timeControlStatus != .playing {
            view.player.play()
        }
    }

    private func applyVolume(to player: AVQueuePlayer) {
        let clamped = max(0, min(volume, 1))
        player.volume = clamped
        player.isMuted = clamped <= 0.001
    }

    private func configureAudio(for volume: Float) {
        guard volume > 0.001 else { return }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(
                .playback,
                mode: .moviePlayback,
                options: [.mixWithOthers]
            )
            try session.setActive(true)
        } catch {
            print("Audio session error: \(error.localizedDescription)")
        }
    }

    final class Coordinator {
        var looper: AVPlayerLooper?
        private weak var player: AVQueuePlayer?
        private var foregroundObserver: NSObjectProtocol?

        init() {
            foregroundObserver = NotificationCenter.default.addObserver(
                forName: UIApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.player?.play()
            }
        }

        func attach(to player: AVQueuePlayer) {
            self.player = player
        }

        deinit {
            if let foregroundObserver {
                NotificationCenter.default.removeObserver(foregroundObserver)
            }
        }
    }
}

final class PlayerUIView: UIView {
    let player = AVQueuePlayer()

    override class var layerClass: AnyClass {
        AVPlayerLayer.self
    }

    private var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspectFill
        backgroundColor = .black
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()

        if window != nil {
            player.play()
        }
    }
}

extension Color {
    init(hex: String) {
        var text = hex.trimmingCharacters(in: .whitespacesAndNewlines)

        if text.hasPrefix("#") {
            text.removeFirst()
        }

        var value: UInt64 = 0
        Scanner(string: text).scanHexInt64(&value)

        if text.count == 6 {
            self.init(
                red: Double((value >> 16) & 0xff) / 255,
                green: Double((value >> 8) & 0xff) / 255,
                blue: Double(value & 0xff) / 255
            )
        } else {
            self.init(red: 0, green: 0, blue: 0)
        }
    }

    func hexString() -> String? {
        let uiColor = UIColor(self)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        guard uiColor.getRed(
            &red,
            green: &green,
            blue: &blue,
            alpha: &alpha
        ) else {
            return nil
        }

        return String(
            format: "#%02X%02X%02X",
            Int(round(red * 255)),
            Int(round(green * 255)),
            Int(round(blue * 255))
        )
    }
}
