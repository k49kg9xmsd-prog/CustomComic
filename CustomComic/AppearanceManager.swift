import SwiftUI
import PhotosUI
import AVKit

@MainActor
final class AppearanceManager: ObservableObject {
    @AppStorage("backgroundStyle") var backgroundStyleRaw = AppBackgroundStyle.solid.rawValue
    @AppStorage("backgroundHex") var backgroundHex = "#000000"
    @AppStorage("backgroundOpacity") var backgroundOpacity = 0.35
    @AppStorage("backgroundVideoVolume") var backgroundVideoVolume = 0.0
    @AppStorage("backgroundBlur") var backgroundBlur = 0.0

    let imageURL: URL
    let videoURL: URL

    init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        imageURL = documents.appendingPathComponent("custom-background-image")
        videoURL = documents.appendingPathComponent("custom-background-video")
    }

    var style: AppBackgroundStyle {
        AppBackgroundStyle(rawValue: backgroundStyleRaw) ?? .solid
    }

    func saveBackgroundImage(_ data: Data) throws {
        try data.write(to: imageURL, options: .atomic)
        objectWillChange.send()
    }

    func saveBackgroundVideo(from source: URL) throws {
        if FileManager.default.fileExists(atPath: videoURL.path) {
            try FileManager.default.removeItem(at: videoURL)
        }
        try FileManager.default.copyItem(at: source, to: videoURL)
        objectWillChange.send()
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
                        .ignoresSafeArea()
                        .blur(radius: appearance.backgroundBlur)
                        .opacity(appearance.backgroundOpacity)
                }

            case .video:
                if FileManager.default.fileExists(atPath: appearance.videoURL.path) {
                    LoopingVideoView(
                        url: appearance.videoURL,
                        volume: Float(appearance.backgroundVideoVolume)
                    )
                    .ignoresSafeArea()
                    .blur(radius: appearance.backgroundBlur)
                    .opacity(appearance.backgroundOpacity)
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
        let item = AVPlayerItem(url: url)
        let looper = AVPlayerLooper(player: view.player, templateItem: item)
        context.coordinator.looper = looper
        view.player.isMuted = volume <= 0.001
        view.player.volume = volume
        view.player.play()
        return view
    }

    func updateUIView(_ view: PlayerUIView, context: Context) {
        view.player.isMuted = volume <= 0.001
        view.player.volume = volume
        if view.player.timeControlStatus != .playing {
            view.player.play()
        }
    }

    final class Coordinator {
        var looper: AVPlayerLooper?
    }
}

final class PlayerUIView: UIView {
    let player = AVQueuePlayer()

    override class var layerClass: AnyClass {
        AVPlayerLayer.self
    }

    var playerLayer: AVPlayerLayer {
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
}

extension Color {
    init(hex: String) {
        var text = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("#") { text.removeFirst() }
        var value: UInt64 = 0
        Scanner(string: text).scanHexInt64(&value)

        let r, g, b: Double
        if text.count == 6 {
            r = Double((value >> 16) & 0xff) / 255
            g = Double((value >> 8) & 0xff) / 255
            b = Double(value & 0xff) / 255
        } else {
            r = 0
            g = 0
            b = 0
        }
        self.init(red: r, green: g, blue: b)
    }
}
