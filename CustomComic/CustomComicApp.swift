import SwiftUI
import UserNotifications

@main
struct CustomComicApp: App {
    @StateObject private var library = ComicLibrary()
    @StateObject private var appearance = AppearanceManager()
    @StateObject private var websiteStore = WebsiteStore()
    @StateObject private var downloadManager = DownloadManager()

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
                .environmentObject(websiteStore)
                .environmentObject(downloadManager)
        }
    }
}
