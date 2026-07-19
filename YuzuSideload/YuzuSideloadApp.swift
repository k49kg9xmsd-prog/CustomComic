import SwiftUI

@main
struct YuzuSideloadApp: App {
    @StateObject private var library = IPALibrary()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(library)
        }
    }
}
