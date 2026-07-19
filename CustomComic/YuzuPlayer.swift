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
    func updateUIView(_ uiView: PlayerContainerView, context: Context) { uiView.playerLayer.player = player }
}

final class PlayerContainerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

struct YuzuPlayerScreen: View {
    @EnvironmentObject private var videoLibrary: VideoLibrary
    @EnvironmentObject private var settings: PlayerSettings
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
    @State private var wasPlayingBeforeSeek = false

    @State private var isSeeking = false
    @State private var seekPreview: Double = 0
    @State private var gestureMode: GestureMode?
    @State private var gestureStartValue: Double = 0
    @State private var hud: PlayerHUD?
    @State private var hideWorkItem: DispatchWorkItem?
    @State private var hudWorkItem: DispatchWorkItem?
    @State private var restartWorkItem: DispatchWorkItem?
    @State private var showRestart = false
    @State private var longPressActive = false

    private var item: VideoItem? { videoLibrary.videos.first { $0.id == itemID } }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let item {
                PlayerLayerView(player: player).ignoresSafeArea()
                gestureSurface

                if controlsVisible {
                    controls(for: item).transition(.opacity)
                }

                if showRestart {
                    restartButton
                        .transition(.move(edge: .leading).combined(with: .opacity))
                        .zIndex(4)
                }

                if let hud {
                    hudView(hud).transition(.scale.combined(with: .opacity)).zIndex(5)
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle").font(.largeTitle)
                    Text("找不到影片").font(.headline)
                }.foregroundStyle(.white)
            }
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .onAppear { if let item { prepare(item) } }
        .onDisappear {
            if let item { saveProgress(item) }
            cleanup()
        }
    }

    private var gestureSurface: some View {
        GeometryReader { proxy in
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    guard settings.gesturesEnabled, settings.singleTapEnabled else { return }
                    withAnimation(.easeOut(duration: 0.18)) { controlsVisible.toggle() }
                    controlsVisible ? scheduleHide() : cancelHide()
                }
                .simultaneousGesture(
                    SpatialTapGesture(count: 2)
                        .onEnded { value in
                            guard settings.gesturesEnabled else { return }
                            let third = proxy.size.width / 3
                            if value.location.x < third {
                                guard settings.leftDoubleTapEnabled else { return }
                                jump(by: -10)
                            } else if value.location.x > third * 2 {
                                guard settings.rightDoubleTapEnabled else { return }
                                jump(by: 10)
                            } else {
                                guard settings.centerDoubleTapEnabled else { return }
                                togglePlayback(showHUD: true)
                            }
                        }
                )
                .gesture(
                    DragGesture(minimumDistance: 12)
                        .onChanged { handleDragChanged($0, size: proxy.size) }
                        .onEnded { handleDragEnded($0, size: proxy.size) }
                )
                .onLongPressGesture(minimumDuration: 0.45, pressing: { pressing in
                    guard settings.gesturesEnabled, settings.longPressSpeedEnabled else { return }
                    if pressing && !longPressActive {
                        longPressActive = true
                        player.rate = 2
                        showHUD(.speed(2))
                    } else if !pressing && longPressActive {
                        longPressActive = false
                        if isPlaying { player.rate = playbackRate }
                        showHUD(.speed(playbackRate))
                    }
                }, perform: {})
        }.ignoresSafeArea()
    }

    @ViewBuilder
    private func controls(for item: VideoItem) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Button {
                    saveProgress(item)
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 20, weight: .bold))
                        .frame(width: 44, height: 44)
                        .background(Color.black.opacity(settings.buttonOpacity), in: Circle())
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title).font(.headline).lineLimit(1)
                    Text(item.category).font(.caption).opacity(0.72)
                }
                Spacer()

                Menu {
                    ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { value in
                        speedButton(Float(value))
                    }
                } label: {
                    Text(speedText)
                        .font(.subheadline.bold())
                        .frame(minWidth: 44, minHeight: 44)
                        .background(Color.black.opacity(settings.buttonOpacity), in: Capsule())
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 10)
            .foregroundStyle(Color(hex: settings.textHex))
            .background(.ultraThinMaterial)
            .background(Color(hex: settings.topBarHex).opacity(settings.topBarOpacity))

            Spacer()

            Button { togglePlayback(showHUD: false) } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(Color(hex: settings.playButtonHex))
                    .frame(width: 86, height: 86)
                    .background(Color.black.opacity(settings.buttonOpacity), in: Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.16), lineWidth: 1))
                    .shadow(color: .black.opacity(0.35), radius: 15)
            }.buttonStyle(.plain)

            Spacer()

            VStack(spacing: 10) {
                PlayerProgressBar(
                    value: isSeeking ? seekPreview : currentTime,
                    duration: duration,
                    played: Color(hex: settings.playedTrackHex),
                    unplayed: Color(hex: settings.unplayedTrackHex),
                    thumb: Color(hex: settings.thumbHex),
                    onEditingChanged: { editing, value in
                        if editing {
                            if !isSeeking { wasPlayingBeforeSeek = isPlaying }
                            isSeeking = true
                            seekPreview = value
                            showHUD(.seek(value, duration))
                            cancelHide()
                        } else {
                            seek(to: value)
                            isSeeking = false
                            if !wasPlayingBeforeSeek { player.pause(); isPlaying = false }
                            scheduleHide()
                        }
                    }
                )

                HStack {
                    Text(VideoItem.timeText(isSeeking ? seekPreview : currentTime))
                    Text("/")
                    Text(VideoItem.timeText(duration))
                    Spacer()
                    Text(isPlaying ? "播放中" : "已暫停")
                        .foregroundStyle(Color(hex: settings.textHex).opacity(0.65))
                }.font(.caption.monospacedDigit())
            }
            .foregroundStyle(Color(hex: settings.textHex))
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 18)
            .background(.ultraThinMaterial)
            .background(Color(hex: settings.bottomBarHex).opacity(settings.bottomBarOpacity))
        }
    }

    private var restartButton: some View {
        VStack {
            Spacer()
            HStack {
                Button {
                    let shouldResume = isPlaying
                    seek(to: 0)
                    if shouldResume { player.play(); player.rate = playbackRate } else { player.pause() }
                    withAnimation { showRestart = false }
                    restartWorkItem?.cancel()
                } label: {
                    Label("從頭播放", systemImage: "arrow.counterclockwise")
                        .font(.subheadline.bold())
                        .foregroundStyle(Color.black)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color(hex: settings.restartHex), in: Capsule())
                        .shadow(color: .black.opacity(0.35), radius: 8)
                }
                Spacer()
            }
            .padding(.leading, 20)
            .padding(.bottom, 86)
        }
    }

    private func speedButton(_ rate: Float) -> some View {
        Button {
            playbackRate = rate
            settings.remember(speed: rate, for: itemID)
            if isPlaying { player.rate = rate }
            showHUD(.speed(rate))
            scheduleHide()
        } label: {
            playbackRate == rate ? AnyView(Label(speedLabel(rate), systemImage: "checkmark")) : AnyView(Text(speedLabel(rate)))
        }
    }

    private func hudView(_ hud: PlayerHUD) -> some View {
        VStack(spacing: 10) {
            Image(systemName: hud.icon).font(.system(size: 34, weight: .semibold))
            Text(hud.text).font(.headline.monospacedDigit())
            if let progress = hud.progress {
                ProgressView(value: progress)
                    .tint(Color(hex: settings.hudTextHex))
                    .frame(width: 130)
            }
        }
        .foregroundStyle(Color(hex: settings.hudTextHex))
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .background(.ultraThinMaterial)
        .background(Color(hex: settings.hudBackgroundHex).opacity(settings.hudOpacity), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func prepare(_ item: VideoItem) {
        guard !hasPrepared else { return }
        hasPrepared = true
        configureAudioSession()
        playbackRate = settings.speed(for: item.id)

        let playerItem = AVPlayerItem(url: videoLibrary.videoURL(for: item))
        player.replaceCurrentItem(with: playerItem)
        player.isMuted = false
        player.volume = 1

        if item.lastPosition > 10 {
            player.seek(to: CMTime(seconds: item.lastPosition, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
            currentTime = item.lastPosition
            showRestartPrompt()
        }

        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main) { _ in
            let seconds = player.currentTime().seconds
            if seconds.isFinite, !isSeeking { currentTime = seconds }
            let itemDuration = player.currentItem?.duration.seconds ?? 0
            if itemDuration.isFinite, itemDuration > 0 { duration = itemDuration }
            isPlaying = player.timeControlStatus == .playing
        }

        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: playerItem, queue: .main) { _ in
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

    private func configureAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch { print("YuzuPlayer Audio Session 設定失敗: \(error.localizedDescription)") }
    }

    private func togglePlayback(showHUD: Bool) {
        if player.timeControlStatus == .playing {
            player.pause(); isPlaying = false
            if showHUD { self.showHUD(.paused) }
            withAnimation { controlsVisible = true }
            cancelHide()
        } else {
            if duration > 0, currentTime >= duration - 0.2 { seek(to: 0) }
            player.play(); player.rate = playbackRate; isPlaying = true
            if showHUD { self.showHUD(.playing) }
            scheduleHide()
        }
    }

    private func jump(by seconds: Double) {
        let target = min(max(currentTime + seconds, 0), max(duration, 0))
        seek(to: target)
        showHUD(seconds < 0 ? .rewind(abs(seconds)) : .forward(seconds))
        scheduleHide()
    }

    private func handleDragChanged(_ value: DragGesture.Value, size: CGSize) {
        guard settings.gesturesEnabled else { return }
        cancelHide()
        let dx = value.translation.width, dy = value.translation.height

        if gestureMode == nil {
            guard max(abs(dx), abs(dy)) > 14 else { return }
            if abs(dx) > abs(dy) * 1.15 {
                guard settings.seekGestureEnabled else { return }
                gestureMode = .seek
                gestureStartValue = currentTime
                seekPreview = currentTime
                isSeeking = true
                wasPlayingBeforeSeek = isPlaying
            } else if value.startLocation.x < size.width / 2 {
                guard settings.brightnessGestureEnabled else { return }
                gestureMode = .brightness
                gestureStartValue = Double(UIScreen.main.brightness)
            } else {
                guard settings.volumeGestureEnabled else { return }
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
            let newValue = min(max(gestureStartValue - Double(dy / max(size.height, 1)), 0), 1)
            UIScreen.main.brightness = CGFloat(newValue)
            showHUD(.brightness(newValue))
        case .volume:
            let newValue = min(max(gestureStartValue - Double(dy / max(size.height, 1)), 0), 1)
            player.volume = Float(newValue)
            showHUD(.volume(newValue))
        case .none: break
        }
    }

    private func handleDragEnded(_ value: DragGesture.Value, size: CGSize) {
        if gestureMode == .seek {
            seek(to: seekPreview)
            isSeeking = false
            if !wasPlayingBeforeSeek { player.pause(); isPlaying = false }
        }
        gestureMode = nil
        scheduleHide()
    }

    private func seek(to seconds: Double) {
        let safe = min(max(seconds, 0), max(duration, 0))
        currentTime = safe
        player.seek(to: CMTime(seconds: safe, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func saveProgress(_ original: VideoItem) {
        let position = player.currentTime().seconds
        let knownDuration = player.currentItem?.duration.seconds ?? original.duration
        guard position.isFinite, knownDuration.isFinite else { return }
        videoLibrary.updateProgress(original, position: position, duration: knownDuration)
    }

    private func cleanup() {
        cancelHide(); hudWorkItem?.cancel(); restartWorkItem?.cancel()
        if let timeObserver { player.removeTimeObserver(timeObserver); self.timeObserver = nil }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver); self.endObserver = nil }
        player.pause()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func scheduleHide() {
        cancelHide()
        guard isPlaying, !isSeeking else { return }
        let work = DispatchWorkItem { withAnimation(.easeOut(duration: 0.25)) { controlsVisible = false } }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
    }

    private func cancelHide() { hideWorkItem?.cancel(); hideWorkItem = nil }

    private func showRestartPrompt() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { showRestart = true }
        restartWorkItem?.cancel()
        let work = DispatchWorkItem { withAnimation(.easeOut(duration: 0.25)) { showRestart = false } }
        restartWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: work)
    }

    private func showHUD(_ value: PlayerHUD) {
        hudWorkItem?.cancel()
        withAnimation(.spring(response: 0.22, dampingFraction: 0.82)) { hud = value }
        let work = DispatchWorkItem {
            withAnimation(.easeOut(duration: 0.18)) { if hud == value { hud = nil } }
        }
        hudWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }

    private var speedText: String { speedLabel(playbackRate) }
    private func speedLabel(_ rate: Float) -> String { rate == 1 ? "1x" : String(format: "%gx", rate) }
}

private struct PlayerProgressBar: View {
    let value: Double
    let duration: Double
    let played: Color
    let unplayed: Color
    let thumb: Color
    let onEditingChanged: (Bool, Double) -> Void

    var body: some View {
        GeometryReader { proxy in
            let fraction = duration > 0 ? min(max(value / duration, 0), 1) : 0
            ZStack(alignment: .leading) {
                Capsule().fill(unplayed.opacity(0.72)).frame(height: 5)
                Capsule().fill(played).frame(width: max(proxy.size.width * fraction, 0), height: 5)
                Circle().fill(thumb).frame(width: 15, height: 15).offset(x: max(proxy.size.width * fraction - 7.5, 0))
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let newFraction = min(max(gesture.location.x / max(proxy.size.width, 1), 0), 1)
                        onEditingChanged(true, newFraction * max(duration, 0))
                    }
                    .onEnded { gesture in
                        let newFraction = min(max(gesture.location.x / max(proxy.size.width, 1), 0), 1)
                        onEditingChanged(false, newFraction * max(duration, 0))
                    }
            )
        }.frame(height: 20)
    }
}

private enum GestureMode { case seek, brightness, volume }

private enum PlayerHUD: Equatable {
    case playing, paused
    case brightness(Double), volume(Double), seek(Double, Double), speed(Float)
    case rewind(Double), forward(Double)

    var icon: String {
        switch self {
        case .playing: return "play.fill"
        case .paused: return "pause.fill"
        case .brightness: return "sun.max.fill"
        case .volume(let value): return value <= 0.01 ? "speaker.slash.fill" : "speaker.wave.2.fill"
        case .seek: return "arrow.left.and.right"
        case .speed: return "speedometer"
        case .rewind: return "gobackward.10"
        case .forward: return "goforward.10"
        }
    }

    var text: String {
        switch self {
        case .playing: return "播放"
        case .paused: return "暫停"
        case .brightness(let value): return "亮度  \(Int((value * 100).rounded()))%"
        case .volume(let value): return "影片音量  \(Int((value * 100).rounded()))%"
        case .seek(let value, let duration): return "\(VideoItem.timeText(value)) / \(VideoItem.timeText(duration))"
        case .speed(let rate): return rate == 1 ? "1x" : String(format: "%gx", rate)
        case .rewind(let value): return "-\(Int(value)) 秒"
        case .forward(let value): return "+\(Int(value)) 秒"
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
