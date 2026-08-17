import SwiftUI
import UIKit
import ImageIO

final class ComicImagePipeline {
    static let shared = ComicImagePipeline()

    private let cache = NSCache<NSString, UIImage>()
    private let queue = DispatchQueue(label: "com.customcomic.image.decode", qos: .userInitiated, attributes: .concurrent)
    private let sizeLock = NSLock()
    private var sizeCache: [String: CGSize] = [:]

    private init() {
        cache.totalCostLimit = 220 * 1024 * 1024
        cache.countLimit = 48
    }

    func imageSize(for url: URL) -> CGSize {
        let key = url.path
        sizeLock.lock()
        if let cached = sizeCache[key] {
            sizeLock.unlock()
            return cached
        }
        sizeLock.unlock()

        var result = CGSize(width: 1, height: 1.4)
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let widthNumber = properties[kCGImagePropertyPixelWidth] as? NSNumber,
           let heightNumber = properties[kCGImagePropertyPixelHeight] as? NSNumber {
            let width = CGFloat(widthNumber.doubleValue)
            let height = CGFloat(heightNumber.doubleValue)
            if width > 0, height > 0 {
                result = CGSize(width: width, height: height)
            }
        }

        sizeLock.lock()
        sizeCache[key] = result
        sizeLock.unlock()
        return result
    }

    func cachedImage(for url: URL, maxPixelSize: CGFloat) -> UIImage? {
        cache.object(forKey: cacheKey(url: url, maxPixelSize: maxPixelSize))
    }

    func load(
        url: URL,
        maxPixelSize: CGFloat,
        completion: @escaping (UIImage?) -> Void
    ) {
        let key = cacheKey(url: url, maxPixelSize: maxPixelSize)
        if let image = cache.object(forKey: key) {
            completion(image)
            return
        }

        queue.async { [weak self] in
            guard let self else { return }
            let image = self.downsample(url: url, maxPixelSize: maxPixelSize)
            if let image {
                let cost = max(1, image.cgImage.map { $0.bytesPerRow * $0.height } ?? 1)
                self.cache.setObject(image, forKey: key, cost: cost)
            }
            DispatchQueue.main.async {
                completion(image)
            }
        }
    }

    private func cacheKey(url: URL, maxPixelSize: CGFloat) -> NSString {
        "\(url.path)|\(Int(maxPixelSize.rounded()))" as NSString
    }

    private func downsample(url: URL, maxPixelSize: CGFloat) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [
            kCGImageSourceShouldCache: false
        ] as CFDictionary) else { return nil }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(256, maxPixelSize),
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
}

struct LocalImage: View {
    let url: URL
    var contentMode: ContentMode = .fit
    var maxPixelSize: CGFloat = 1400

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                ZStack {
                    Rectangle().fill(.gray.opacity(0.16))
                    ProgressView()
                        .tint(.secondary)
                }
            }
        }
        .onAppear { load(url) }
        .onChange(of: url) { load($0) }
    }

    private func load(_ targetURL: URL) {
        image = ComicImagePipeline.shared.cachedImage(for: targetURL, maxPixelSize: maxPixelSize)
        ComicImagePipeline.shared.load(url: targetURL, maxPixelSize: maxPixelSize) { loaded in
            guard targetURL == url else { return }
            image = loaded
        }
    }
}
