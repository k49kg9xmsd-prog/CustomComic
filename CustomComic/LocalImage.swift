import SwiftUI
import UIKit

struct LocalImage: View {
    let url: URL
    var contentMode: ContentMode = .fit

    var body: some View {
        Group {
            if let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                ZStack {
                    Rectangle().fill(.gray.opacity(0.2))
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
