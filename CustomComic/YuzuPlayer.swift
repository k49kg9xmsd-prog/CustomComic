import SwiftUI
import AVFoundation
import UIKit

struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerContainerView {
        let view = PlayerContainerView()
        view.playerLayer.videoGravity = .resizeAspect
        view.playerLayer.player = player
        return view
    }

    func updateUIView(_ uiView: PlayerContainerView, context: Context) {
        uiView.playerLayer.player = player
    }
}

final class PlayerContainerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

struct YuzuPlayerScreen: View {
    @EnvironmentObject private var videoLibrary: VideoLibrary
    @Environment(\.dismiss) private var dismiss

    let itemID: UUID

    @State private var player = AVPlayer()
    @State private var timeObserver: Any?
    @State private var endObserver: NSObjectProtocol?
    @State private var hasPrepared = false

    @State private var isPlaying = false
    @State private var controlsVisible = true
    @State private var currentTime: Double = 0
    @State private var duration: Double = 0
    @State private var playbackRate: Float = 1

    @State private var isSeeking = false
    @State private var seekPreview: Double = 0
    @State private var gestureMode: GestureMode?
    @State private var gestureStartValue: Double = 0
    @State private var hud: PlayerHUD?
    @State private var hideWorkItem: DispatchWorkItem?

    private var item: VideoItem? {
        videoLibrary.videos.first { $0.id == itemID }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let item {
                PlayerLayerView(player: player)
                    .ignoresSafeArea()

                gestureSurface

                if controlsVisible {
                    controls(for: item)
                        .transition(.opacity)
                }

                if let hud {
                    hudView(hud)
                        .transition(.scale.combined(with: .opacity))
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                    Text("找不到影片").font(.headline)
                }
                .foregroundStyle(.white)
            }
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .onAppear {
            if let item { prepare(item) }
        }
        .onDisappear {
            if let item { saveProgress(item) }
            cleanup()
        }
    }

    private var gestureSurface: some View {
        GeometryReader { proxy in
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    togglePlayback(showHUD: true)
                }
                .onTapGesture(count: 1) {
                    withAnimation(.easeOut(duration: 0.18)) {
                        controlsVisible.toggle()
                    }
                    if controlsVisible { scheduleHide() } else { cancelHide() }
                }
                .gesture(
                    DragGesture(minimumDistance: 12)
                        .onChanged { value in
                            handleDragChanged(value, size: proxy.size)
                        }
                        .onEnded { value in
                            handleDragEnded(value, size: proxy.size)
                        }
                )
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private func controls(for item: VideoItem) -> some View {
        ZStack {
            LinearGradient(
                colors: [.black.opacity(0.72), .clear, .black.opacity(0.82)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    Button {
                        saveProgress(item)
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 20, weight: .bold))
                            .frame(width: 44, height: 44)
                            .background(.black.opacity(0.32), in: Circle())
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(.headline)
                            .lineLimit(1)
                        Text(item.category)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.72))
                    }

                    Spacer()

                    Menu {
                        speedButton(0.5)
                        speedButton(0.75)
                        speedButton(1.0)
                        speedButton(1.25)
                        speedButton(1.5)
                        speedButton(2.0)
                    } label: {
                        Text(speedText)
                            .font(.subheadline.bold())
                            .frame(minWidth: 44, minHeight: 44)
                            .background(.black.opacity(0.32), in: Capsule())
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)

                Spacer()

                Button {
                    togglePlayback(showHUD: false)
                } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 38, weight: .semibold))
                        .frame(width: 86, height: 86)
                        .background(.black.opacity(0.48), in: Circle())
                        .overlay(Circle().stroke(.white.opacity(0.16), lineWidth: 1))
                        .shadow(color: .black.opacity(0.35), radius: 15)
                }
                .buttonStyle(.plain)

                Spacer()

                VStack(spacing: 10) {
                    Slider(
                        value: Binding(
                            get: { isSeeking ? seekPreview : currentTime },
                            set: { value in
                                isSeeking = true
                                seekPreview = value
                                showHUD(.seek(value, duration))
                                cancelHide()
                            }
                        ),
                        in: 0...max(duration, 1),
                        onEditingChanged: { editing in
                            if !editing {
                                seek(to: seekPreview)
                                isSeeking = false
                                scheduleHide()
                            }
                        }
                    )
                    .tint(.white)

                    HStack {
                        Text(VideoItem.timeText(isSeeking ? seekPreview : currentTime))
                        Text("/")
                        Text(VideoItem.timeText(duration))
                        Spacer()
                        Text("雙擊播放/暫停")
                            .foregroundStyle(.white.opacity(0.62))
                    }
                    .font(.caption.monospacedDigit())
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 18)
            }
            .foregroundStyle(.white)
        }
    }

    private func speedButton(_ rate: Float) -> some View {
        Button {
            playbackRate = rate
            if isPlaying { player.rate = rate }
            showHUD(.speed(rate))
            scheduleHide()
        } label: {
            if playbackRate == rate {
                Label(speedLabel(rate), systemImage: "checkmark")
            } else {
                Text(speedLabel(rate))
            }
        }
    }

    private func hudView(_ hud: PlayerHUD) -> some View {
        VStack(spacing: 10) {
            Image(systemName: hud.icon)
                .font(.system(size: 34, weight: .semibold))
            Text(hud.text)
                .font(.headline.monospacedDigit())
            if let progress = hud.progress {
                ProgressView(value: progress)
                    .tint(.white)
                    .frame(width: 130)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .background(.black.opacity(0.68), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func prepare(_ item: VideoItem) {
        guard !hasPrepared else { return }
        hasPrepared = true

        let playerItem = AVPlayerItem(url: videoLibrary.videoURL(for: item))
        player.replaceCurrentItem(with: playerItem)
        player.volume = 1

        if item.lastPosition > 1 {
            player.seek(
                to: CMTime(seconds: item.lastPosition, preferredTimescale: 600),
                toleranceBefore: .zero,
                toleranceAfter: .zero
            )
            currentTime = item.lastPosition
        }

        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
            queue: .main
        ) { _ in
            let seconds = player.currentTime().seconds
            if seconds.isFinite, !isSeeking { currentTime = seconds }

            let itemDuration = player.currentItem?.duration.seconds ?? 0
            if itemDuration.isFinite, itemDuration > 0 { duration = itemDuration }

            isPlaying = player.timeControlStatus == .playing
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { _ in
            isPlaying = false
            currentTime = duration
            videoLibrary.updateProgress(item, position: duration, duration: duration)
            withAnimation { controlsVisible = true }
            cancelHide()
        }

        player.play()
        player.rate = playbackRate
        isPlaying = true
        scheduleHide()
    }

    private func togglePlayback(showHUD: Bool) {
        if player.timeControlStatus == .playing {
            player.pause()
            isPlaying = false
            if showHUD { self.showHUD(.paused) }
            withAnimation { controlsVisible = true }
            cancelHide()
        } else {
            if duration > 0, currentTime >= duration - 0.2 {
                seek(to: 0)
            }
            player.play()
            player.rate = playbackRate
            isPlaying = true
            if showHUD { self.showHUD(.playing) }
            scheduleHide()
        }
    }

    private func handleDragChanged(_ value: DragGesture.Value, size: CGSize) {
        cancelHide()
        let dx = value.translation.width
        let dy = value.translation.height

        if gestureMode == nil {
            guard max(abs(dx), abs(dy)) > 14 else { return }
            if abs(dx) > abs(dy) {
                gestureMode = .seek
                gestureStartValue = currentTime
                seekPreview = currentTime
                isSeeking = true
            } else if value.startLocation.x < size.width / 2 {
                gestureMode = .brightness
                gestureStartValue = Double(UIScreen.main.brightness)
            } else {
                gestureMode = .volume
                gestureStartValue = Double(player.volume)
            }
        }

        switch gestureMode {
        case .seek:
            let secondsPerWidth = max(duration / 2.5, 60) / max(size.width, 1)
            seekPreview = min(max(gestureStartValue + Double(dx) * secondsPerWidth, 0), max(duration, 0))
            showHUD(.seek(seekPreview, duration))
        case .brightness:
            let value = min(max(gestureStartValue - Double(dy / max(size.height, 1)), 0), 1)
            UIScreen.main.brightness = CGFloat(value)
            showHUD(.brightness(value))
        case .volume:
            let value = min(max(gestureStartValue - Double(dy / max(size.height, 1)), 0), 1)
            player.volume = Float(value)
            showHUD(.volume(value))
        case .none:
            break
        }
    }

    private func handleDragEnded(_ value: DragGesture.Value, size: CGSize) {
        if gestureMode == .seek {
            seek(to: seekPreview)
            isSeeking = false
        }
        gestureMode = nil
        scheduleHide()
    }

    private func seek(to seconds: Double) {
        let safe = min(max(seconds, 0), max(duration, 0))
        currentTime = safe
        player.seek(
            to: CMTime(seconds: safe, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
    }

    private func saveProgress(_ original: VideoItem) {
        let position = player.currentTime().seconds
        let knownDuration = player.currentItem?.duration.seconds ?? original.duration
        guard position.isFinite, knownDuration.isFinite else { return }
        videoLibrary.updateProgress(original, position: position, duration: knownDuration)
    }

    private func cleanup() {
        cancelHide()
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        player.pause()
    }

    private func scheduleHide() {
        cancelHide()
        guard isPlaying else { return }
        let work = DispatchWorkItem {
            withAnimation(.easeOut(duration: 0.25)) {
                controlsVisible = false
            }
        }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
    }

    private func cancelHide() {
        hideWorkItem?.cancel()
        hideWorkItem = nil
    }

    private func showHUD(_ value: PlayerHUD) {
        withAnimation(.spring(response: 0.22, dampingFraction: 0.82)) {
            hud = value
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            withAnimation(.easeOut(duration: 0.18)) {
                if hud == value { hud = nil }
            }
        }
    }

    private var speedText: String { speedLabel(playbackRate) }

    private func speedLabel(_ rate: Float) -> String {
        rate == 1 ? "1x" : String(format: "%gx", rate)
    }
}

private enum GestureMode {
    case seek
    case brightness
    case volume
}

private enum PlayerHUD: Equatable {
    case playing
    case paused
    case brightness(Double)
    case volume(Double)
    case seek(Double, Double)
    case speed(Float)

    var icon: String {
        switch self {
        case .playing: return "play.fill"
        case .paused: return "pause.fill"
        case .brightness: return "sun.max.fill"
        case .volume(let value): return value <= 0.01 ? "speaker.slash.fill" : "speaker.wave.2.fill"
        case .seek: return "arrow.left.and.right"
        case .speed: return "speedometer"
        }
    }

    var text: String {
        switch self {
        case .playing: return "播放"
        case .paused: return "暫停"
        case .brightness(let value): return "亮度  \(Int((value * 100).rounded()))%"
        case .volume(let value): return "音量  \(Int((value * 100).rounded()))%"
        case .seek(let value, let duration): return "\(VideoItem.timeText(value)) / \(VideoItem.timeText(duration))"
        case .speed(let rate): return rate == 1 ? "1x" : String(format: "%gx", rate)
        }
    }

    var progress: Double? {
        switch self {
        case .brightness(let value), .volume(let value): return value
        case .seek(let value, let duration): return duration > 0 ? value / duration : 0
        default: return nil
        }
    }
}
