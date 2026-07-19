import SwiftUI
import UIKit

struct ZoomableImagePage: UIViewRepresentable {
    let url: URL
    var onSingleTap: ((CGFloat) -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(onSingleTap: onSingleTap)
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scroll = UIScrollView()
        scroll.backgroundColor = .black
        scroll.delegate = context.coordinator
        scroll.minimumZoomScale = 1
        scroll.maximumZoomScale = 6
        scroll.showsHorizontalScrollIndicator = false
        scroll.showsVerticalScrollIndicator = false
        scroll.bouncesZoom = true
        scroll.contentInsetAdjustmentBehavior = .never

        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.backgroundColor = .black
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.isUserInteractionEnabled = true
        scroll.addSubview(imageView)

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            imageView.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
            imageView.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor)
        ])

        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        let singleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleSingleTap(_:)))
        singleTap.require(toFail: doubleTap)
        scroll.addGestureRecognizer(doubleTap)
        scroll.addGestureRecognizer(singleTap)

        context.coordinator.imageView = imageView
        context.coordinator.scrollView = scroll
        context.coordinator.load(url: url, targetWidth: UIScreen.main.bounds.width * UIScreen.main.scale)
        return scroll
    }

    func updateUIView(_ scroll: UIScrollView, context: Context) {
        context.coordinator.onSingleTap = onSingleTap
        guard context.coordinator.currentPath != url.path else { return }
        scroll.setZoomScale(1, animated: false)
        scroll.contentOffset = .zero
        context.coordinator.load(url: url, targetWidth: max(scroll.bounds.width, UIScreen.main.bounds.width) * UIScreen.main.scale)
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var imageView: UIImageView?
        weak var scrollView: UIScrollView?
        var currentPath: String?
        var onSingleTap: ((CGFloat) -> Void)?

        init(onSingleTap: ((CGFloat) -> Void)?) { self.onSingleTap = onSingleTap }

        func load(url: URL, targetWidth: CGFloat) {
            currentPath = url.path
            let expectedPath = url.path
            imageView?.image = ComicImagePipeline.shared.cachedImage(for: url, maxPixelSize: targetWidth)
            ComicImagePipeline.shared.load(url: url, maxPixelSize: targetWidth) { [weak self] image in
                guard let self, self.currentPath == expectedPath else { return }
                self.imageView?.image = image
            }
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            guard let imageView else { return }
            let horizontal = max(0, (scrollView.bounds.width - imageView.frame.width) / 2)
            let vertical = max(0, (scrollView.bounds.height - imageView.frame.height) / 2)
            scrollView.contentInset = UIEdgeInsets(top: vertical, left: horizontal, bottom: vertical, right: horizontal)
        }

        @objc func handleSingleTap(_ gesture: UITapGestureRecognizer) {
            guard let scrollView, scrollView.bounds.width > 0 else { return }
            // 放大時單擊只收放工具列，不誤觸翻頁。
            if scrollView.zoomScale > 1.05 {
                onSingleTap?(0.5)
                return
            }
            let point = gesture.location(in: scrollView)
            onSingleTap?(min(max(point.x / scrollView.bounds.width, 0), 1))
        }

        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scrollView else { return }
            if scrollView.zoomScale > 1.05 {
                scrollView.setZoomScale(1, animated: true)
            } else {
                let point = gesture.location(in: imageView)
                let scale: CGFloat = 2.5
                scrollView.zoom(to: CGRect(
                    x: point.x - scrollView.bounds.width / scale / 2,
                    y: point.y - scrollView.bounds.height / scale / 2,
                    width: scrollView.bounds.width / scale,
                    height: scrollView.bounds.height / scale
                ), animated: true)
            }
        }
    }
}

struct ContinuousZoomReader: UIViewRepresentable {
    let urls: [URL]
    let initialPage: Int
    @Binding var currentPage: Int

    func makeCoordinator() -> Coordinator { Coordinator(currentPage: $currentPage) }

    func makeUIView(context: Context) -> UIScrollView {
        let outer = UIScrollView()
        outer.backgroundColor = .black
        outer.delegate = context.coordinator
        outer.minimumZoomScale = 1
        outer.maximumZoomScale = 5
        outer.bouncesZoom = true
        outer.contentInsetAdjustmentBehavior = .never

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 0
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        outer.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: outer.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: outer.contentLayoutGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: outer.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: outer.contentLayoutGuide.bottomAnchor),
            stack.widthAnchor.constraint(equalTo: outer.frameLayoutGuide.widthAnchor)
        ])

        context.coordinator.stack = stack
        context.coordinator.outer = outer
        context.coordinator.reload(urls: urls, initialPage: initialPage)
        return outer
    }

    func updateUIView(_ outer: UIScrollView, context: Context) {
        context.coordinator.currentPage = $currentPage
        let paths = urls.map(\.path)
        if context.coordinator.paths != paths {
            context.coordinator.reload(urls: urls, initialPage: currentPage)
        } else {
            context.coordinator.scrollToPageIfNeeded(currentPage, animated: false)
        }
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var stack: UIStackView?
        weak var outer: UIScrollView?
        var paths: [String] = []
        var urls: [URL] = []
        var imageViews: [UIImageView] = []
        var currentPage: Binding<Int>
        private var visiblePage = 0
        private var isProgrammaticScroll = false
        private var loadedPages = Set<Int>()

        init(currentPage: Binding<Int>) { self.currentPage = currentPage }

        func reload(urls: [URL], initialPage: Int) {
            guard let stack, let outer else { return }
            stack.arrangedSubviews.forEach { stack.removeArrangedSubview($0); $0.removeFromSuperview() }
            self.urls = urls
            paths = urls.map(\.path)
            imageViews = []
            loadedPages.removeAll()

            // 只讀圖片尺寸建立排版，不在主執行緒解碼全部原圖。
            for url in urls {
                let imageView = UIImageView()
                imageView.contentMode = .scaleAspectFit
                imageView.backgroundColor = .black
                imageView.clipsToBounds = true
                imageView.translatesAutoresizingMaskIntoConstraints = false
                let size = ComicImagePipeline.shared.imageSize(for: url)
                let ratio = size.width > 0 ? size.height / size.width : 1.4
                stack.addArrangedSubview(imageView)
                imageView.heightAnchor.constraint(equalTo: imageView.widthAnchor, multiplier: ratio).isActive = true
                imageViews.append(imageView)
            }

            outer.layoutIfNeeded()
            let target = min(max(initialPage, 0), max(0, imageViews.count - 1))
            visiblePage = target
            currentPage.wrappedValue = target
            scrollToPage(target, animated: false)
            loadPages(around: target)
        }

        func scrollToPageIfNeeded(_ page: Int, animated: Bool) {
            let target = min(max(page, 0), max(0, imageViews.count - 1))
            guard target != visiblePage else { loadPages(around: target); return }
            scrollToPage(target, animated: animated)
        }

        private func scrollToPage(_ page: Int, animated: Bool) {
            guard let outer, imageViews.indices.contains(page) else { return }
            outer.layoutIfNeeded()
            let maximumY = max(0, outer.contentSize.height - outer.bounds.height)
            let targetY = min(max(0, imageViews[page].frame.minY), maximumY)
            isProgrammaticScroll = true
            visiblePage = page
            loadPages(around: page)
            outer.setContentOffset(CGPoint(x: 0, y: targetY), animated: animated)
            if !animated { DispatchQueue.main.async { [weak self] in self?.isProgrammaticScroll = false } }
        }

        private func loadPages(around page: Int) {
            guard !urls.isEmpty else { return }
            let loadRange = max(0, page - 2)...min(urls.count - 1, page + 3)
            let keepRange = max(0, page - 5)...min(urls.count - 1, page + 6)

            for index in Array(loadedPages) where !keepRange.contains(index) {
                imageViews[index].image = nil
                loadedPages.remove(index)
            }

            let maxPixels = max(1200, (outer?.bounds.width ?? UIScreen.main.bounds.width) * UIScreen.main.scale)
            for index in loadRange where !loadedPages.contains(index) {
                loadedPages.insert(index)
                let expectedPath = urls[index].path
                ComicImagePipeline.shared.load(url: urls[index], maxPixelSize: maxPixels) { [weak self] image in
                    guard let self,
                          self.urls.indices.contains(index),
                          self.urls[index].path == expectedPath,
                          self.loadedPages.contains(index) else { return }
                    self.imageViews[index].image = image
                }
            }
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { stack }
        func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) { isProgrammaticScroll = false }
        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { updateVisiblePage(scrollView) }
        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            if !decelerate { updateVisiblePage(scrollView) }
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard scrollView.zoomScale <= 1.05, !imageViews.isEmpty else { return }
            updateVisiblePage(scrollView)
        }

        private func updateVisiblePage(_ scrollView: UIScrollView) {
            let centerY = scrollView.contentOffset.y + scrollView.bounds.height / 2
            // 從目前頁附近找，避免每個捲動 frame 掃描整本漫畫。
            let lower = max(0, visiblePage - 3)
            let upper = min(imageViews.count - 1, visiblePage + 4)
            var closest = visiblePage
            var best = CGFloat.greatestFiniteMagnitude
            for index in lower...upper {
                let distance = abs(imageViews[index].frame.midY - centerY)
                if distance < best { best = distance; closest = index }
            }
            guard closest != visiblePage else { return }
            visiblePage = closest
            loadPages(around: closest)
            if !isProgrammaticScroll, currentPage.wrappedValue != closest {
                currentPage.wrappedValue = closest
            }
        }
    }
}
