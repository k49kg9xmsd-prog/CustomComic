import SwiftUI

@main
struct CustomComicApp: App {
    @StateObject private var library = ComicLibrary()

    var body: some Scene {
        WindowGroup {
            LibraryView()
                .environmentObject(library)
        }
    }
}
