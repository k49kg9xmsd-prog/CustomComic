import SwiftUI
import UserNotifications

@main
struct CustomComicApp: App {
    @StateObject private var library = ComicLibrary()
    @StateObject private var appearance = AppearanceManager()
    @StateObject private var videoLibrary = VideoLibrary()
    @StateObject private var websiteStore = WebsiteStore()
    @StateObject private var downloadManager = DownloadManager()
    @StateObject private var playerSettings = PlayerSettings.shared

    init() {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound, .badge]
        ) { _, _ in }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(library)
                .environmentObject(appearance)
                .environmentObject(videoLibrary)
                .environmentObject(websiteStore)
                .environmentObject(downloadManager)
                .environmentObject(playerSettings)
        }
    }
}
