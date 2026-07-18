import SwiftUI
import UIKit

struct ZoomableImagePage: UIViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator()
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

        let doubleTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleDoubleTap(_:))
        )
        doubleTap.numberOfTapsRequired = 2
        scroll.addGestureRecognizer(doubleTap)

        context.coordinator.imageView = imageView
        context.coordinator.scrollView = scroll
        imageView.image = UIImage(contentsOfFile: url.path)
        return scroll
    }

    func updateUIView(_ scroll: UIScrollView, context: Context) {
        let newPath = url.path
        if context.coordinator.currentPath != newPath {
            context.coordinator.currentPath = newPath
            context.coordinator.imageView?.image = UIImage(contentsOfFile: newPath)
            scroll.setZoomScale(1, animated: false)
            scroll.contentOffset = .zero
        }
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var imageView: UIImageView?
        weak var scrollView: UIScrollView?
        var currentPath: String?

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            imageView
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            guard let imageView else { return }
            let horizontal = max(0, (scrollView.bounds.width - imageView.frame.width) / 2)
            let vertical = max(0, (scrollView.bounds.height - imageView.frame.height) / 2)
            scrollView.contentInset = UIEdgeInsets(
                top: vertical,
                left: horizontal,
                bottom: vertical,
                right: horizontal
            )
        }

        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scrollView else { return }
            if scrollView.zoomScale > 1.05 {
                scrollView.setZoomScale(1, animated: true)
            } else {
                let point = gesture.location(in: imageView)
                let targetScale: CGFloat = 2.5
                let width = scrollView.bounds.width / targetScale
                let height = scrollView.bounds.height / targetScale
                scrollView.zoom(
                    to: CGRect(
                        x: point.x - width / 2,
                        y: point.y - height / 2,
                        width: width,
                        height: height
                    ),
                    animated: true
                )
            }
        }
    }
}

struct ContinuousZoomReader: UIViewRepresentable {
    let urls: [URL]
    let initialPage: Int
    let onVisiblePageChanged: (Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onVisiblePageChanged: onVisiblePageChanged)
    }

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
        stack.distribution = .fill
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
        let paths = urls.map(\.path)
        if context.coordinator.paths != paths {
            context.coordinator.reload(urls: urls, initialPage: initialPage)
        }
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var stack: UIStackView?
        weak var outer: UIScrollView?
        var paths: [String] = []
        var imageViews: [UIImageView] = []
        var onVisiblePageChanged: (Int) -> Void

        init(onVisiblePageChanged: @escaping (Int) -> Void) {
            self.onVisiblePageChanged = onVisiblePageChanged
        }

        func reload(urls: [URL], initialPage: Int) {
            guard let stack, let outer else { return }
            stack.arrangedSubviews.forEach {
                stack.removeArrangedSubview($0)
                $0.removeFromSuperview()
            }

            paths = urls.map(\.path)
            imageViews = []

            for url in urls {
                let imageView = UIImageView()
                imageView.image = UIImage(contentsOfFile: url.path)
                imageView.contentMode = .scaleAspectFit
                imageView.backgroundColor = .black
                imageView.clipsToBounds = true
                imageView.translatesAutoresizingMaskIntoConstraints = false

                let image = imageView.image
                let ratio: CGFloat
                if let image, image.size.width > 0 {
                    ratio = image.size.height / image.size.width
                } else {
                    ratio = 1.4
                }

                stack.addArrangedSubview(imageView)
                imageView.heightAnchor.constraint(
                    equalTo: imageView.widthAnchor,
                    multiplier: ratio
                ).isActive = true
                imageViews.append(imageView)
            }

            outer.layoutIfNeeded()
            let target = min(max(initialPage, 0), max(0, imageViews.count - 1))
            if imageViews.indices.contains(target) {
                let y = imageViews[target].frame.minY
                outer.setContentOffset(CGPoint(x: 0, y: y), animated: false)
            }
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            stack
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard scrollView.zoomScale <= 1.05, !imageViews.isEmpty else { return }
            let centerY = scrollView.contentOffset.y + scrollView.bounds.height / 2
            var closest = 0
            var best = CGFloat.greatestFiniteMagnitude
            for (index, view) in imageViews.enumerated() {
                let distance = abs(view.frame.midY - centerY)
                if distance < best {
                    best = distance
                    closest = index
                }
            }
            onVisiblePageChanged(closest)
        }
    }
}
