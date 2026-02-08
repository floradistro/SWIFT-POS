//
//  ImageCache.swift
//  Whale
//
//  High-performance image caching for POS product grid.
//  Optimized for fast startup with controlled concurrency.
//

import SwiftUI
import UIKit

// MARK: - Image Cache

actor ImageCache {
    static let shared = ImageCache()

    private var cache = NSCache<NSString, UIImage>()
    private var inFlightTasks: [URL: Task<UIImage?, Never>] = [:]
    private var prefetchQueue: [URL] = []
    private var isPrefetching = false

    // CRITICAL: Hard limit on concurrent downloads to prevent gesture gate timeout
    // Too many concurrent requests = too many state updates = UI freeze
    private let maxConcurrentDownloads = 4
    private var activeDownloads = 0

    // Shared URLSession for all image downloads - reusing connections
    private let session: URLSession

    private init() {
        cache.countLimit = 300  // Reduced from 500
        cache.totalCostLimit = 75 * 1024 * 1024 // 75MB (reduced from 100MB)

        // Configure a shared URLSession for image loading
        let config = URLSessionConfiguration.default
        config.urlCache = nil  // We have our own cache
        config.timeoutIntervalForRequest = 10  // Reduced from 15 - fail fast
        config.timeoutIntervalForResource = 20  // Reduced from 30
        config.httpMaximumConnectionsPerHost = 4  // Match maxConcurrentDownloads
        session = URLSession(configuration: config)
    }

    /// Wait for a download slot to become available
    private func acquireSlot() async {
        while activeDownloads >= maxConcurrentDownloads {
            // Yield and check again - simple backpressure
            try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
        }
        activeDownloads += 1
    }

    /// Release a download slot
    private func releaseSlot() {
        activeDownloads = max(0, activeDownloads - 1)
    }

    /// Get cached image synchronously (for checking cache only)
    func cachedImage(for url: URL) -> UIImage? {
        let key = url.absoluteString as NSString
        return cache.object(forKey: key)
    }

    /// Get cached image or fetch if needed
    func image(for url: URL, priority: TaskPriority = .medium) async -> UIImage? {
        let key = url.absoluteString as NSString

        // Check cache first (fast path)
        if let cached = cache.object(forKey: key) {
            return cached
        }

        // Check if already fetching
        if let existingTask = inFlightTasks[url] {
            return await existingTask.value
        }

        // Start new fetch with controlled priority
        let task = Task<UIImage?, Never>(priority: priority) {
            await fetchImage(url: url, key: key)
        }

        inFlightTasks[url] = task
        let result = await task.value
        inFlightTasks[url] = nil

        return result
    }

    private func fetchImage(url: URL, key: NSString) async -> UIImage? {
        // Wait for a download slot - prevents overwhelming network + UI
        await acquireSlot()
        defer { releaseSlot() }

        do {
            // Use shared URLSession for connection reuse
            let (data, response) = try await session.data(from: url)

            // Verify we got image data
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200,
                  let image = UIImage(data: data) else {
                return nil
            }

            // Downsample large images to reduce memory
            // IMPORTANT: Run on background thread to avoid blocking main thread
            let maxDimension: CGFloat = 500
            let downsampledImage = await Self.downsampleOffMainThread(image, maxDimension: maxDimension)

            // Cache the processed image (cost calculation also off main thread)
            let cost = await Task.detached(priority: .utility) {
                downsampledImage.jpegData(compressionQuality: 0.8)?.count ?? 0
            }.value
            cache.setObject(downsampledImage, forKey: key, cost: cost)

            return downsampledImage
        } catch {
            // Silently fail - don't log or retry to prevent state churn
            return nil
        }
    }

    /// Downsample image to reduce memory footprint
    /// Runs on background thread to avoid blocking UI
    private static func downsampleOffMainThread(_ image: UIImage, maxDimension: CGFloat) async -> UIImage {
        await Task.detached(priority: .utility) {
            let size = image.size
            guard size.width > maxDimension || size.height > maxDimension else {
                return image
            }

            let scale = maxDimension / max(size.width, size.height)
            let newSize = CGSize(width: size.width * scale, height: size.height * scale)

            // UIGraphicsImageRenderer is synchronous but now runs off main thread
            let renderer = UIGraphicsImageRenderer(size: newSize)
            return renderer.image { _ in
                image.draw(in: CGRect(origin: .zero, size: newSize))
            }
        }.value
    }

    /// Pre-fetch multiple images with controlled concurrency
    /// Only prefetches first batch immediately, rest are queued
    func prefetch(urls: [URL]) {
        // Filter out already cached URLs
        let uncachedUrls = urls.filter { cachedImage(for: $0) == nil }

        guard !uncachedUrls.isEmpty else { return }

        // Add to queue
        prefetchQueue.append(contentsOf: uncachedUrls)

        // Start processing if not already running
        if !isPrefetching {
            Task(priority: .background) {
                await processPrefetchQueue()
            }
        }
    }

    private func processPrefetchQueue() async {
        isPrefetching = true

        while !prefetchQueue.isEmpty {
            // Take batch of URLs to process
            let batchSize = min(maxConcurrentDownloads, prefetchQueue.count)
            let batch = Array(prefetchQueue.prefix(batchSize))
            prefetchQueue.removeFirst(batchSize)

            // Process batch concurrently
            await withTaskGroup(of: Void.self) { group in
                for url in batch {
                    group.addTask(priority: .background) {
                        _ = await self.image(for: url, priority: .background)
                    }
                }
            }

            // Small delay between batches to prevent overwhelming
            try? await Task.sleep(for: .milliseconds(50))
        }

        isPrefetching = false
    }

    /// Clear cache
    func clear() {
        cache.removeAllObjects()
        prefetchQueue.removeAll()
    }
}

// MARK: - Cached Async Image

struct CachedAsyncImage: View {
    let url: URL?
    var placeholderLogoUrl: URL? = nil
    var dimAmount: Double = 0.0  // 0 = no dim, 0.3 = 30% darker

    @State private var image: UIImage?
    @State private var loadState: LoadState = .idle

    private enum LoadState {
        case idle
        case loading
        case loaded
        case failed
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .overlay(Color.black.opacity(dimAmount))  // Subtle dim for consistency
            } else if loadState == .loading {
                // Subtle placeholder - no spinner to reduce overhead
                Design.Colors.backgroundSecondary
            } else {
                // Failed or no URL - show store logo or icon placeholder
                placeholderView
            }
        }
        .task(id: url) {
            await loadImage()
        }
    }

    @ViewBuilder
    private var placeholderView: some View {
        if let logoUrl = placeholderLogoUrl {
            // Show store logo as placeholder
            StoreLogoPlaceholder(logoUrl: logoUrl)
        } else {
            // Fallback icon placeholder
            Design.Colors.backgroundSecondary
                .overlay(
                    Image(systemName: "photo")
                        .foregroundStyle(Design.Colors.Text.ghost)
                        .font(Design.Typography.title2)
                )
        }
    }

    private func loadImage() async {
        guard let url else {
            loadState = .failed
            return
        }

        // Check cache synchronously first for instant display
        if let cached = await ImageCache.shared.cachedImage(for: url) {
            image = cached
            loadState = .loaded
            return
        }

        // CRITICAL: Delay image loading to let first frame render
        // This prevents gesture gate timeout by allowing UI to stabilize
        // before starting async work that triggers state updates
        try? await Task.sleep(nanoseconds: 50_000_000) // 50ms

        // Check if view is still mounted (task not cancelled)
        guard !Task.isCancelled else { return }

        loadState = .loading

        if let loadedImage = await ImageCache.shared.image(for: url) {
            // Only update if we're still showing this URL
            image = loadedImage
            loadState = .loaded
        } else {
            loadState = .failed
        }
    }
}

// MARK: - Store Logo Placeholder

struct StoreLogoPlaceholder: View {
    let logoUrl: URL

    @State private var logoImage: UIImage?

    var body: some View {
        ZStack {
            // Dark background
            Design.Colors.backgroundSecondary

            // Store logo - subtle and centered
            if let logoImage {
                Image(uiImage: logoImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 60, maxHeight: 60)
                    .opacity(0.25)  // Very subtle
            } else {
                // Fallback while loading logo
                Image(systemName: "storefront")
                    .foregroundStyle(Design.Colors.Text.ghost)
                    .font(Design.Typography.title1)
            }
        }
        .task {
            if let cached = await ImageCache.shared.cachedImage(for: logoUrl) {
                logoImage = cached
            } else if let loaded = await ImageCache.shared.image(for: logoUrl) {
                logoImage = loaded
            }
        }
    }
}
