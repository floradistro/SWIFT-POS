//
//  StageManagerRoot.swift
//  Whale
//
//  Root wrapper that adds Stage Manager functionality.
//  Pinch-in to reveal window grid, tap to select.
//

import SwiftUI
import WebKit
import Combine

struct StageManagerRoot<Content: View>: View {
    @ObservedObject var store = StageManagerStore.shared
    @State private var pinchScale: CGFloat = 1.0
    let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    /// Check if the active fullscreen window is a POS app (which has its own dock)
    private var isActiveWindowPOS: Bool {
        // Only hide SmartDock when Stage Manager is hidden AND active window is POS
        guard !store.isVisible, !store.windows.isEmpty else { return false }
        guard let activeWindow = store.windows.first(where: { $0.id == store.activeWindowId }) else { return false }

        if case .app = activeWindow.type {
            return true
        }
        return false
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Stage Manager background (always show when empty or visible)
                if store.isVisible || store.windows.isEmpty {
                    StageManagerBackground()
                }

                // Content layer
                if store.windows.isEmpty {
                    // Empty state - just show background, dock handles everything
                    Color.clear
                }
                // Active fullscreen window (when Stage Manager hidden and has windows)
                else if !store.isVisible {
                    // Use if-let to find active window directly - ensures view updates when window changes
                    if let activeWindow = store.windows.first(where: { $0.id == store.activeWindowId }) {
                        fullscreenWindow(for: activeWindow, geo: geo)
                    }
                }
                // Stage Manager grid view
                else {
                    StageManagerGrid(geo: geo, content: content)
                }

                // Smart Dock - show unless a POS window is active fullscreen
                // POS windows have their own dock, so hide SmartDock only for POS
                // Creations and other windows should still show SmartDock
                if !isActiveWindowPOS {
                    SmartDockView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea(.all)
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: store.isVisible)
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: store.activeWindowId)
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: store.windows.isEmpty)
        .animation(.interactiveSpring(response: 0.15), value: pinchScale)
        .modifier(WindowPinchGesture(
            onChanged: { scale in
                // Don't trigger pinch when screen is locked
                if scale < 1.0 && !store.isVisible && !store.windows.isEmpty && !store.isScreenLocked {
                    pinchScale = max(0.5, scale)
                }
            },
            onEnded: { scale in
                // Don't trigger Stage Manager when screen is locked
                if scale < 0.75 && !store.isVisible && !store.windows.isEmpty && !store.isScreenLocked {
                    store.show()
                }
                withAnimation(.spring(response: 0.3)) {
                    pinchScale = 1.0
                }
            }
        ))
    }

    // MARK: - Fullscreen Window (when Stage Manager hidden)

    @ViewBuilder
    private func fullscreenWindow(for window: StageManagerStore.StageWindow, geo: GeometryProxy) -> some View {
        switch window.type {
        case .app(_):
            // App handles its own safe areas - don't override
            windowContent(for: window, geo: geo)
                .scaleEffect(min(1.0, pinchScale))
        case .creation:
            // Creations handle safe areas in CSS, so ignore them here
            windowContent(for: window, geo: geo)
                .ignoresSafeArea(.all)
                .scaleEffect(min(1.0, pinchScale))
        }
    }

    // MARK: - Window Content

    @ViewBuilder
    private func windowContent(for window: StageManagerStore.StageWindow, geo: GeometryProxy) -> some View {
        switch window.type {
        case .app(let sessionId):
            // Inject per-window POS session via environment
            let session = POSWindowSessionManager.shared.session(for: sessionId)
            let _ = print("🪟 StageManagerRoot.windowContent - sessionId: \(sessionId), hasLocation: \(session.location != nil), locationId: \(session.locationId?.uuidString ?? "nil")")
            content()
                .environment(\.posWindowSession, session)
        case .creation(let id, let url, let reactCode):
            CreationWindowView(
                creationId: id,
                url: url,
                reactCode: reactCode,
                name: window.name,
                refreshTrigger: store.refreshTrigger[window.id]
            )
        }
    }
}

// MARK: - Empty Launcher View

struct EmptyLauncherView: View {
    var body: some View {
        // Smart AI Chat Dock - centered hub for messages and apps
        SmartDockView()
    }
}


// MARK: - Stage Manager Grid (Apple-style)

struct StageManagerGrid<Content: View>: View {
    let geo: GeometryProxy
    let content: () -> Content
    @ObservedObject var store = StageManagerStore.shared

    // MARK: - Dynamic Layout Calculations

    private var windowCount: Int { store.windows.count }

    // Determine grid dimensions based on window count
    private var gridLayout: (rows: Int, cols: Int) {
        switch windowCount {
        case 0, 1: return (1, 1)
        case 2: return (1, 2)
        case 3: return (1, 3)
        case 4: return (2, 2)
        case 5, 6: return (2, 3)
        case 7, 8: return (2, 4)
        default: return (3, Int(ceil(Double(windowCount) / 3.0)))
        }
    }

    // Available space for windows (accounting for padding and dock)
    private var availableWidth: CGFloat {
        geo.size.width - 80 // 40pt padding on each side
    }

    private var availableHeight: CGFloat {
        geo.size.height - 140 - geo.safeAreaInsets.top - geo.safeAreaInsets.bottom // dock + padding
    }

    // Spacing between windows
    private var spacing: CGFloat { 24 }
    private var labelHeight: CGFloat { 32 }

    // Calculate optimal window size to fill available space
    private var windowSize: CGSize {
        let (rows, cols) = gridLayout

        // Calculate max width per window
        let totalHSpacing = CGFloat(cols - 1) * spacing
        let maxWidthPerWindow = (availableWidth - totalHSpacing) / CGFloat(cols)

        // Calculate max height per window (including label)
        let totalVSpacing = CGFloat(rows - 1) * spacing
        let totalLabelHeight = CGFloat(rows) * labelHeight
        let maxHeightPerWindow = (availableHeight - totalVSpacing - totalLabelHeight) / CGFloat(rows)

        // Maintain aspect ratio of screen
        let aspectRatio = geo.size.width / geo.size.height

        // Fit within both constraints while maintaining aspect ratio
        let widthFromHeight = maxHeightPerWindow * aspectRatio
        let heightFromWidth = maxWidthPerWindow / aspectRatio

        if widthFromHeight <= maxWidthPerWindow {
            // Height is the constraint
            return CGSize(width: widthFromHeight, height: maxHeightPerWindow)
        } else {
            // Width is the constraint
            return CGSize(width: maxWidthPerWindow, height: heightFromWidth)
        }
    }

    // Scale factor relative to full screen
    private var windowScale: CGFloat {
        windowSize.width / geo.size.width
    }

    var body: some View {
        ZStack {
            // Window grid - centered
            VStack(spacing: spacing) {
                Spacer()

                gridContent

                Spacer()
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 100)
        }
    }

    // MARK: - Grid Content

    @ViewBuilder
    private var gridContent: some View {
        let (rows, cols) = gridLayout

        VStack(spacing: spacing) {
            ForEach(0..<rows, id: \.self) { row in
                HStack(spacing: spacing) {
                    ForEach(0..<cols, id: \.self) { col in
                        let index = row * cols + col
                        if index < store.windows.count {
                            windowThumbnail(store.windows[index])
                        } else {
                            // Empty placeholder to maintain grid
                            Color.clear
                                .frame(width: windowSize.width, height: windowSize.height + labelHeight)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Window Thumbnail (True scaled content)

    @ViewBuilder
    private func windowThumbnail(_ window: StageManagerStore.StageWindow) -> some View {
        let isActive = store.activeWindowId == window.id
        let cornerRadius: CGFloat = 12

        // In launcher architecture, all windows can be closed
        let canClose = true

        VStack(spacing: 8) {
            // Actual window content, scaled down
            ZStack(alignment: .topTrailing) {
                windowContent(for: window)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .scaleEffect(windowScale)
                    .frame(width: windowSize.width, height: windowSize.height)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(
                                isActive ? Color.white.opacity(0.6) : Color.white.opacity(0.2),
                                lineWidth: isActive ? 2.5 : 1
                            )
                    )
                    .shadow(color: .black.opacity(0.4), radius: 20, y: 10)
                    .allowsHitTesting(false)
                    .overlay {
                        // Transparent overlay to capture taps
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture {
                                Haptics.medium()
                                store.select(window)
                            }
                            .contextMenu {
                                contextMenuItems(for: window)
                            }
                    }

                // Close button (top-right corner)
                if canClose {
                    Button {
                        Haptics.heavy()
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            store.close(window)
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .black.opacity(0.6))
                            .frame(width: 44, height: 44)
                            .contentShape(Circle())
                    }
                    .buttonStyle(ScaleButtonStyle())
                    .offset(x: 8, y: -8)
                }
            }

            // Label
            Text(window.name)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
                .frame(maxWidth: windowSize.width)
        }
    }

    // MARK: - Window Content

    @ViewBuilder
    private func windowContent(for window: StageManagerStore.StageWindow) -> some View {
        switch window.type {
        case .app(let sessionId):
            let session = POSWindowSessionManager.shared.session(for: sessionId)
            content()
                .environment(\.posWindowSession, session)
        case .creation(let id, let url, let reactCode):
            CreationWindowView(
                creationId: id,
                url: url,
                reactCode: reactCode,
                name: window.name,
                refreshTrigger: store.refreshTrigger[window.id]
            )
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func contextMenuItems(for window: StageManagerStore.StageWindow) -> some View {
        Button {
            store.select(window)
        } label: {
            Label("Open", systemImage: "arrow.up.left.and.arrow.down.right")
        }

        if case .creation = window.type {
            Button {
                store.refresh(window)
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
        }

        Divider()

        // In launcher architecture, all windows can be closed
        Button(role: .destructive) {
            Haptics.heavy()
            store.close(window)
        } label: {
            Label("Close Window", systemImage: "xmark")
        }
    }

}

// MARK: - Add Window Button (separate view for @State)

struct AddWindowButtonView: View {
    let width: CGFloat
    let height: CGFloat
    @State private var showLauncher = false

    var body: some View {
        ZStack {
            VStack(spacing: 8) {
                Button {
                    Haptics.medium()
                    showLauncher = true
                } label: {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(.white.opacity(0.2), lineWidth: 1)
                        )
                        .overlay(
                            Image(systemName: "plus")
                                .font(.system(size: 40, weight: .ultraLight))
                                .foregroundStyle(.white.opacity(0.6))
                        )
                        .frame(width: width, height: height)
                        .shadow(color: .black.opacity(0.3), radius: 15, y: 8)
                }
                .buttonStyle(StageManagerButtonStyle())

                Text("New")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
            }

            // App Launcher Modal
            if showLauncher {
                AppLauncherModal(isPresented: $showLauncher)
                    .environmentObject(SessionObserver.shared)
            }
        }
    }
}

// MARK: - Window Card with Swipe to Close & Context Menu

struct WindowCard<Content: View>: View {
    let window: StageManagerStore.StageWindow
    let isActive: Bool
    let scale: CGFloat
    let offset: CGSize
    let cornerRadius: CGFloat
    let isStageVisible: Bool
    let geo: GeometryProxy
    let onSelect: () -> Void
    let onClose: () -> Void
    let onRefresh: (() -> Void)?
    @ViewBuilder let content: () -> Content

    @State private var dragOffset: CGFloat = 0
    @State private var isDragging = false

    init(
        window: StageManagerStore.StageWindow,
        isActive: Bool,
        scale: CGFloat,
        offset: CGSize,
        cornerRadius: CGFloat,
        isStageVisible: Bool,
        geo: GeometryProxy,
        onSelect: @escaping () -> Void,
        onClose: @escaping () -> Void,
        onRefresh: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.window = window
        self.isActive = isActive
        self.scale = scale
        self.offset = offset
        self.cornerRadius = cornerRadius
        self.isStageVisible = isStageVisible
        self.geo = geo
        self.onSelect = onSelect
        self.onClose = onClose
        self.onRefresh = onRefresh
        self.content = content
    }

    private var canClose: Bool {
        // Can only close creation windows, not the main app
        if case .creation = window.type { return true }
        return false
    }

    private var closeThreshold: CGFloat { -120 }

    private var strokeColor: Color {
        guard isStageVisible else { return .clear }
        return isActive ? Color.white.opacity(0.5) : Color.white.opacity(0.2)
    }

    var body: some View {
        // When active and fullscreen, don't constrain with frame so ignoresSafeArea works
        let isFullscreen = !isStageVisible && isActive

        Group {
            if isFullscreen {
                // Active fullscreen - no frame constraint, content can expand to edges
                content()
                    .ignoresSafeArea(.all)
            } else {
                // Stage Manager mode - constrain and scale, disable content interaction
                content()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    .allowsHitTesting(false) // Disable content interaction in Stage Manager
            }
        }
        .scaleEffect(isFullscreen ? 1.0 : scale, anchor: .center)
        .offset(x: isFullscreen ? 0 : offset.width, y: isFullscreen ? 0 : offset.height + (isStageVisible ? dragOffset : 0))
        .shadow(color: .black.opacity(isStageVisible ? 0.6 : 0), radius: 40, y: 20)
            .overlay {
                // Only show stroke in Stage Manager mode
                if isStageVisible {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(strokeColor, lineWidth: isActive ? 3 : 1)
                        .scaleEffect(scale)
                        .offset(x: offset.width, y: offset.height + dragOffset)
                }
            }
            // Interactive overlay for Stage Manager gestures
            .overlay {
                if isStageVisible {
                    Color.clear
                        .frame(width: geo.size.width * scale, height: geo.size.height * scale)
                        .contentShape(Rectangle())
                        .position(x: geo.size.width / 2 + offset.width, y: geo.size.height / 2 + offset.height + dragOffset)
                        // Context menu
                        .contextMenu {
                            if canClose {
                                Button {
                                    onRefresh?()
                                } label: {
                                    Label("Refresh", systemImage: "arrow.clockwise")
                                }

                                Button {
                                    onSelect()
                                } label: {
                                    Label("Open", systemImage: "arrow.up.left.and.arrow.down.right")
                                }

                                Divider()

                                Button(role: .destructive) {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                        dragOffset = -geo.size.height
                                    }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                        onClose()
                                    }
                                } label: {
                                    Label("Close Window", systemImage: "xmark")
                                }
                            } else {
                                Button {
                                    onSelect()
                                } label: {
                                    Label("Open", systemImage: "arrow.up.left.and.arrow.down.right")
                                }
                            }
                        }
                        // Swipe up to close
                        .gesture(
                            canClose ?
                            DragGesture()
                                .onChanged { value in
                                    isDragging = true
                                    if value.translation.height < 0 {
                                        dragOffset = value.translation.height
                                    }
                                }
                                .onEnded { value in
                                    isDragging = false
                                    if value.translation.height < closeThreshold {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                            dragOffset = -geo.size.height
                                        }
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                            onClose()
                                        }
                                    } else {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                            dragOffset = 0
                                        }
                                    }
                                }
                            : nil
                        )
                        // Tap to select
                        .onTapGesture {
                            onSelect()
                        }
                }
            }
            // Close indicator when dragging up
            .overlay {
                if isStageVisible && canClose && dragOffset < -20 {
                    VStack {
                        Spacer()
                        HStack {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title)
                            Text("Release to close")
                                .font(.subheadline.weight(.medium))
                        }
                        .foregroundStyle(dragOffset < closeThreshold ? .red : .white.opacity(0.8))
                        .padding(.vertical, 12)
                        .padding(.horizontal, 20)
                        .background(.ultraThinMaterial, in: Capsule())
                        .scaleEffect(min(1.0, abs(dragOffset) / CGFloat(60)))
                        .opacity(Double(min(1.0, abs(dragOffset) / CGFloat(40))))
                    }
                    .offset(y: -60)
                    .allowsHitTesting(false)
                }
            }
    }
}

// MARK: - Creation Window View

struct CreationWindowView: View {
    let creationId: String
    let url: String?
    let reactCode: String?
    let name: String
    let refreshTrigger: UUID?

    var body: some View {
        let _ = print("🪟 CreationWindowView[\(name)]: Rendering locally")
        CreationHTMLRenderer(
            creationId: creationId,
            reactCode: reactCode ?? "",
            name: name,
            refreshTrigger: refreshTrigger
        )
    }
}

// MARK: - Creation HTML Renderer (renders react_code locally)

struct CreationHTMLRenderer: View {
    let creationId: String
    let reactCode: String
    let name: String
    let refreshTrigger: UUID?

    @State private var isLoading = true
    @State private var loadError: String?
    @State private var currentCode: String = ""  // Track code changes for hot reload
    @State private var hasInitialized = false
    @State private var webViewOpacity: Double = 1.0  // For smooth hot reload transitions

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                // WebView - edge-to-edge on sides/bottom, but respects top safe area (status bar)
                CreationHTMLWebView(
                    html: buildRenderHTML(code: currentCode),
                    isLoading: $isLoading,
                    loadError: $loadError
                )
                .id(currentCode.hashValue)  // Recreate WebView when code actually changes
                .frame(width: geometry.size.width + geometry.safeAreaInsets.leading + geometry.safeAreaInsets.trailing,
                       height: geometry.size.height + geometry.safeAreaInsets.bottom)
                .offset(x: -geometry.safeAreaInsets.leading, y: 0)
                .opacity(webViewOpacity)
                .onChange(of: isLoading) { _, newLoading in
                    // Fade in when loading completes (for hot reload smoothness)
                    if !newLoading && hasInitialized {
                        withAnimation(.easeIn(duration: 0.15)) {
                            webViewOpacity = 1.0
                        }
                    }
                }

                // Loading state - only show on FIRST load
                if isLoading && !hasInitialized {
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                            .tint(.white)
                        Text("Rendering...")
                            .font(.headline)
                            .foregroundStyle(.white)
                        Text(name)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
                }

                // Error state
                if let error = loadError {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundStyle(.orange)
                        Text("Render Error")
                            .font(.headline)
                            .foregroundStyle(.white)
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.6))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .onAppear {
                currentCode = reactCode
            }
            .onChange(of: reactCode) { oldCode, newCode in
                // Hot reload - code actually changed
                if oldCode != newCode && !newCode.isEmpty {
                    print("🔥 Hot reload: reactCode changed (\(oldCode.count) -> \(newCode.count) chars)")
                    hasInitialized = true  // Don't show loading after first load
                    loadError = nil
                    // Quick fade out before loading new code (prevents black flash)
                    webViewOpacity = 0.7
                    currentCode = newCode
                }
            }
        }
        .ignoresSafeArea(.all)
        .background(Color.black)
    }

    private func buildRenderHTML(code: String) -> String {
        // Get store context from SessionObserver
        let storeId = SessionObserver.shared.storeId?.uuidString.lowercased() ?? ""
        let locationId = SessionObserver.shared.selectedLocation?.id.uuidString.lowercased() ?? ""

        // DEBUG: Print what we're using
        print("🪟 [DEBUG] buildRenderHTML:")
        print("🪟 [DEBUG]   storeId: '\(storeId)' (empty: \(storeId.isEmpty))")
        print("🪟 [DEBUG]   locationId: '\(locationId)' (empty: \(locationId.isEmpty))")
        print("🪟 [DEBUG]   creationId: '\(creationId)'")
        print("🪟 [DEBUG]   code length: \(code.count)")

        // Strip import statements from react code (libraries loaded via CDN)
        let codeWithoutImports = code
            .replacingOccurrences(of: "^import\\s+.*?from\\s+['\"][^'\"]+['\"];?\\s*$", with: "", options: .regularExpression)
            .replacingOccurrences(of: "^import\\s+['\"][^'\"]+['\"];?\\s*$", with: "", options: .regularExpression)
            .replacingOccurrences(of: "^import\\s*\\{[^}]*\\}\\s*from\\s*['\"][^'\"]+['\"];?\\s*$", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Only escape characters that would break Swift string interpolation
        // Do NOT escape JS template literal chars - the React code uses them legitimately
        let safeReactCode = codeWithoutImports
            .replacingOccurrences(of: "\\(", with: "\\\\(")  // Escape Swift interpolation

        return """
        <!DOCTYPE html>
        <html>
        <head>
          <meta charset="UTF-8">
          <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no, viewport-fit=cover">
          <title>\(name)</title>

          <!-- Google Fonts -->
          <link rel="preconnect" href="https://fonts.googleapis.com">
          <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
          <link href="https://fonts.googleapis.com/css2?family=Inter:wght@100;200;300;400;500;600;700;800;900&family=Poppins:wght@100;200;300;400;500;600;700;800;900&family=Playfair+Display:wght@400;500;600;700;800;900&family=Space+Grotesk:wght@300;400;500;600;700&family=Roboto:wght@100;300;400;500;700;900&family=JetBrains+Mono:wght@400;500;600;700&display=swap" rel="stylesheet">

          <!-- Font Awesome Icons -->
          <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.1/css/all.min.css">

          <!-- Tailwind CSS -->
          <script src="https://cdn.tailwindcss.com"></script>
          <script>
            tailwind.config = {
              theme: {
                extend: {
                  fontFamily: {
                    sans: ['Inter', 'system-ui', 'sans-serif'],
                    display: ['Poppins', 'system-ui', 'sans-serif'],
                    serif: ['Playfair Display', 'Georgia', 'serif'],
                    mono: ['JetBrains Mono', 'monospace'],
                    space: ['Space Grotesk', 'sans-serif'],
                    roboto: ['Roboto', 'sans-serif'],
                  }
                }
              }
            }
          </script>

          <!-- Core React -->
          <script src="https://unpkg.com/react@18/umd/react.production.min.js" crossorigin></script>
          <script src="https://unpkg.com/react-dom@18/umd/react-dom.production.min.js" crossorigin></script>

          <!-- Animation Libraries -->
          <script src="https://unpkg.com/framer-motion@11/dist/framer-motion.js" crossorigin></script>
          <script src="https://unpkg.com/gsap@3/dist/gsap.min.js" crossorigin></script>
          <script src="https://unpkg.com/gsap@3/dist/ScrollTrigger.min.js" crossorigin></script>
          <script src="https://cdn.jsdelivr.net/npm/canvas-confetti@1.9.2/dist/confetti.browser.min.js"></script>

          <!-- 3D Graphics -->
          <script src="https://unpkg.com/three@0.160.0/build/three.min.js" crossorigin></script>

          <!-- Charts -->
          <script src="https://unpkg.com/recharts@2.10.3/umd/Recharts.js" crossorigin></script>

          <!-- React Router (for multi-page apps) -->
          <script src="https://unpkg.com/react-router-dom@6/dist/umd/react-router-dom.production.min.js" crossorigin></script>

          <!-- Utilities -->
          <script src="https://unpkg.com/lodash@4/lodash.min.js" crossorigin></script>
          <script src="https://unpkg.com/luxon@3/build/global/luxon.min.js" crossorigin></script>

          <!-- Icons -->
          <script src="https://unpkg.com/lucide@latest/dist/umd/lucide.min.js" crossorigin></script>

          <!-- Babel for JSX -->
          <script src="https://unpkg.com/@babel/standalone/babel.min.js"></script>

          <!-- Global library setup -->
          <script>
            // Framer Motion
            if (window.Motion) {
              window.motion = window.Motion.motion;
              window.AnimatePresence = window.Motion.AnimatePresence;
              window.useAnimation = window.Motion.useAnimation;
              window.useMotionValue = window.Motion.useMotionValue;
              window.useTransform = window.Motion.useTransform;
              window.useSpring = window.Motion.useSpring;
              window.useInView = window.Motion.useInView;
            }
            // GSAP
            if (window.gsap && window.ScrollTrigger) {
              window.gsap.registerPlugin(window.ScrollTrigger);
            }
            // Three.js
            if (window.THREE) {
              window.Three = window.THREE;
            }
            // Recharts
            if (window.Recharts) {
              window.LineChart = window.Recharts.LineChart;
              window.BarChart = window.Recharts.BarChart;
              window.PieChart = window.Recharts.PieChart;
              window.AreaChart = window.Recharts.AreaChart;
              window.XAxis = window.Recharts.XAxis;
              window.YAxis = window.Recharts.YAxis;
              window.CartesianGrid = window.Recharts.CartesianGrid;
              window.Tooltip = window.Recharts.Tooltip;
              window.Legend = window.Recharts.Legend;
              window.Line = window.Recharts.Line;
              window.Bar = window.Recharts.Bar;
              window.Pie = window.Recharts.Pie;
              window.Area = window.Recharts.Area;
              window.Cell = window.Recharts.Cell;
              window.ResponsiveContainer = window.Recharts.ResponsiveContainer;
            }
            // React Router - expose components globally
            if (window.ReactRouterDOM) {
              window.HashRouter = window.ReactRouterDOM.HashRouter;
              window.BrowserRouter = window.ReactRouterDOM.BrowserRouter;
              window.MemoryRouter = window.ReactRouterDOM.MemoryRouter;
              window.Routes = window.ReactRouterDOM.Routes;
              window.Route = window.ReactRouterDOM.Route;
              window.Link = window.ReactRouterDOM.Link;
              window.NavLink = window.ReactRouterDOM.NavLink;
              window.Navigate = window.ReactRouterDOM.Navigate;
              window.Outlet = window.ReactRouterDOM.Outlet;
              window.useNavigate = window.ReactRouterDOM.useNavigate;
              window.useLocation = window.ReactRouterDOM.useLocation;
              window.useParams = window.ReactRouterDOM.useParams;
              window.useSearchParams = window.ReactRouterDOM.useSearchParams;
              window.useMatch = window.ReactRouterDOM.useMatch;
              // Router wrapper component that uses HashRouter (works without server)
              window.Router = window.HashRouter;
            }
            // Confetti helper
            window.fireConfetti = function(options) {
              if (window.confetti) {
                return window.confetti({ particleCount: 100, spread: 70, origin: { y: 0.6 }, ...options });
              }
            };
            // Three.js scene helper
            window.useThreeScene = function(canvasRef, setupFn, deps) {
              var loadingState = window.useStore ? window.useStore.productsWithInventory() : { loading: false };
              React.useEffect(function() {
                if (loadingState.loading) return;
                if (!canvasRef.current || typeof THREE === 'undefined') return;
                var cleanup = setupFn(canvasRef.current);
                return function() { if (typeof cleanup === 'function') cleanup(); };
              }, [loadingState.loading].concat(deps || []));
            };
          </script>

          <!-- WhaleStore - Live Data Kernel -->
          <script>
            \(buildWhaleStoreScript(storeId: storeId, locationId: locationId, creationId: creationId))
          </script>

          <style>
            * { margin: 0; padding: 0; box-sizing: border-box; }
            html, body {
              font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
              overflow-x: hidden;
              overflow-y: auto;
              background: #000;
              width: 100%;
              height: 100%;
            }
            /* Content starts below status bar, background extends to top */
            #root {
              min-height: 100vh;
              width: 100%;
              position: relative;
              padding-top: env(safe-area-inset-top, 47px);
              padding-left: env(safe-area-inset-left, 0);
              padding-right: env(safe-area-inset-right, 0);
              padding-bottom: env(safe-area-inset-bottom, 0);
            }
            .render-error {
              min-height: 100vh;
              display: flex;
              flex-direction: column;
              align-items: center;
              justify-content: center;
              background: #000;
              color: #fff;
              padding: 20px;
              text-align: center;
            }
            .render-error h2 { color: #ef4444; margin-bottom: 12px; }
            .render-error code {
              display: block;
              margin-top: 16px;
              padding: 12px;
              background: rgba(255,255,255,0.1);
              border-radius: 8px;
              font-size: 12px;
              color: #f87171;
            }
          </style>
        </head>
        <body>
          <div id="root"></div>

          <script>
            window.__renderError = null;
            window.onerror = function(msg, url, lineNo, columnNo, error) {
              console.error('[Creation] Runtime Error:', msg);
              showErrorFallback('Runtime Error', msg);
              return true;
            };

            function showErrorFallback(title, message) {
              var root = document.getElementById('root');
              if (root && !root.dataset.errorShown) {
                root.dataset.errorShown = 'true';
                root.innerHTML = '<div class="render-error"><h2>' + title + '</h2><code>' + (message || 'Unknown').substring(0, 200) + '</code></div>';
              }
            }

            window.__renderTimeout = setTimeout(function() {
              var root = document.getElementById('root');
              if (root && root.children.length === 0 && !root.dataset.errorShown) {
                showErrorFallback('Timeout', 'Creation failed to render');
              }
            }, 10000);

            function waitForDependencies(callback, maxWait) {
              var waited = 0;
              var interval = setInterval(function() {
                if (window.Recharts && !window.ResponsiveContainer) {
                  window.ResponsiveContainer = window.Recharts.ResponsiveContainer;
                  window.LineChart = window.Recharts.LineChart;
                  window.BarChart = window.Recharts.BarChart;
                  window.PieChart = window.Recharts.PieChart;
                  window.AreaChart = window.Recharts.AreaChart;
                  window.XAxis = window.Recharts.XAxis;
                  window.YAxis = window.Recharts.YAxis;
                  window.CartesianGrid = window.Recharts.CartesianGrid;
                  window.Tooltip = window.Recharts.Tooltip;
                  window.Legend = window.Recharts.Legend;
                  window.Line = window.Recharts.Line;
                  window.Bar = window.Recharts.Bar;
                  window.Pie = window.Recharts.Pie;
                  window.Area = window.Recharts.Area;
                  window.Cell = window.Recharts.Cell;
                }
                // Setup React Router if not already done
                if (window.ReactRouterDOM && !window.HashRouter) {
                  window.HashRouter = window.ReactRouterDOM.HashRouter;
                  window.MemoryRouter = window.ReactRouterDOM.MemoryRouter;
                  window.Routes = window.ReactRouterDOM.Routes;
                  window.Route = window.ReactRouterDOM.Route;
                  window.Link = window.ReactRouterDOM.Link;
                  window.NavLink = window.ReactRouterDOM.NavLink;
                  window.Navigate = window.ReactRouterDOM.Navigate;
                  window.Outlet = window.ReactRouterDOM.Outlet;
                  window.useNavigate = window.ReactRouterDOM.useNavigate;
                  window.useLocation = window.ReactRouterDOM.useLocation;
                  window.useParams = window.ReactRouterDOM.useParams;
                  window.Router = window.HashRouter;
                }
                var ready = !!window.useStore && !!window.React && !!window.ReactDOM;
                if (ready) {
                  clearInterval(interval);
                  callback();
                } else if (waited > maxWait) {
                  clearInterval(interval);
                  showErrorFallback('Load Error', 'Dependencies not loaded');
                }
                waited += 50;
              }, 50);
            }
          </script>

          <script type="text/babel">
            waitForDependencies(function() {
              try {
                \(safeReactCode)

                if (typeof App === 'undefined') {
                  throw new Error('App component not found');
                }

                clearTimeout(window.__renderTimeout);
                const root = ReactDOM.createRoot(document.getElementById('root'));
                root.render(<App />);
                console.log('[Creation] Rendered successfully');
              } catch (error) {
                console.error('[Creation] Render Error:', error);
                clearTimeout(window.__renderTimeout);
                showErrorFallback('Render Error', error.message);
              }
            }, 8000);
          </script>
        </body>
        </html>
        """
    }

    private func buildWhaleStoreScript(storeId: String, locationId: String, creationId: String) -> String {
        // Use the same credentials as the rest of the app
        let supabaseUrl = SupabaseConfig.baseURL
        let supabaseKey = SupabaseConfig.anonKey

        return """
        (function(window) {
          'use strict';

          const SUPABASE_URL = '\(supabaseUrl)';
          const SUPABASE_KEY = '\(supabaseKey)';
          const STORE_ID = '\(storeId)';
          const LOCATION_ID = '\(locationId.isEmpty ? "" : locationId)';
          const CREATION_ID = '\(creationId)';

          console.log('[WhaleStore] Initializing:', { STORE_ID: STORE_ID, LOCATION_ID: LOCATION_ID, CREATION_ID: CREATION_ID });

          const cache = new Map();
          const POLL_INTERVAL = 3000;

          async function supabaseQuery(table, filters, options) {
            const params = new URLSearchParams();
            params.set('select', options?.select || '*');
            if (STORE_ID && table !== 'stores') params.set('store_id', 'eq.' + STORE_ID);
            if (table === 'stores' && STORE_ID) params.set('id', 'eq.' + STORE_ID);

            const url = SUPABASE_URL + '/rest/v1/' + table + '?' + params.toString();
            console.log('[WhaleStore] Query:', table, url);
            try {
              const response = await fetch(url, {
                headers: {
                  'apikey': SUPABASE_KEY,
                  'Authorization': 'Bearer ' + SUPABASE_KEY,
                  'Content-Type': 'application/json',
                  'Accept': 'application/json'
                }
              });
              console.log('[WhaleStore] Response status:', response.status);
              if (!response.ok) {
                const text = await response.text();
                console.error('[WhaleStore] Query failed:', response.status, text);
                throw new Error('Query failed: ' + response.status);
              }
              const data = await response.json();
              console.log('[WhaleStore] Got', data.length, 'rows from', table);
              return data;
            } catch (e) {
              console.error('[WhaleStore] Query error:', table, e.message);
              return [];
            }
          }

          function useQuery(entity, filters, options) {
            const React = window.React;
            const [data, setData] = React.useState([]);
            const [loading, setLoading] = React.useState(true);

            React.useEffect(function() {
              let mounted = true;
              supabaseQuery(entity, filters, options).then(function(result) {
                if (mounted) { setData(result); setLoading(false); }
              });
              return function() { mounted = false; };
            }, [entity]);

            return { data: data, loading: loading };
          }

          function useStoreInfo() {
            const result = useQuery('stores', null, {
              select: 'id,store_name,logo_url,banner_url,store_tagline,brand_colors'
            });
            return {
              data: result.data?.[0] || null,
              loading: result.loading,
              name: result.data?.[0]?.store_name,
              logo: result.data?.[0]?.logo_url
            };
          }

          function useProductsWithInventory() {
            const React = window.React;
            const [data, setData] = React.useState([]);
            const [loading, setLoading] = React.useState(true);

            React.useEffect(function() {
              let mounted = true;
              console.log('[WhaleStore] useProductsWithInventory: Starting fetch');

              async function fetchProducts() {
                try {
                  if (!STORE_ID) {
                    throw new Error('No STORE_ID configured');
                  }

                  // Build select clause - inventory join depends on whether we have a location
                  var inventorySelect = LOCATION_ID
                    ? 'inventory:inventory_with_holds!inner(id,product_id,location_id,total_quantity,held_quantity,available_quantity)'
                    : 'inventory:inventory_with_holds(id,product_id,location_id,total_quantity,held_quantity,available_quantity)';

                  var selectFields = [
                    'id', 'name', 'description', 'sku', 'price', 'regular_price', 'sale_price', 'on_sale',
                    'featured_image', 'custom_fields', 'pricing_data', 'store_id', 'primary_category_id',
                    'pricing_schema_id', 'status',
                    'primary_category:categories!primary_category_id(id,name)',
                    'pricing_schema:pricing_schemas(id,name,tiers)',
                    inventorySelect
                  ].join(',');

                  // Build URL with proper PostgREST syntax
                  var baseUrl = SUPABASE_URL + '/rest/v1/products';
                  var params = [];
                  params.push('select=' + encodeURIComponent(selectFields));
                  params.push('store_id=eq.' + STORE_ID);
                  params.push('or=(status.eq.active,status.eq.published)');
                  params.push('order=name');

                  // Location filter for inventory
                  if (LOCATION_ID) {
                    params.push('inventory.location_id=eq.' + LOCATION_ID);
                  }
                  params.push('inventory.available_quantity=gte.1');

                  var url = baseUrl + '?' + params.join('&');
                  console.log('[WhaleStore] Fetching products:', url.substring(0, 120));

                  var response = await fetch(url, {
                    headers: {
                      'apikey': SUPABASE_KEY,
                      'Authorization': 'Bearer ' + SUPABASE_KEY,
                      'Content-Type': 'application/json',
                      'Accept': 'application/json'
                    }
                  });

                  console.log('[WhaleStore] Response status:', response.status);

                  if (!response.ok) {
                    var errText = await response.text();
                    console.error('[WhaleStore] Query failed:', response.status, errText);
                    throw new Error('Query failed: ' + response.status);
                  }

                  var products = await response.json();
                  console.log('[WhaleStore] Got', products.length, 'products');

                  // Filter client-side to ensure we only have products with inventory
                  var productsWithStock = products.filter(function(p) {
                    if (!p.inventory) return false;
                    // inventory can be array or object depending on query
                    var inv = Array.isArray(p.inventory) ? p.inventory[0] : p.inventory;
                    return inv && (inv.available_quantity > 0 || inv.total_quantity > 0);
                  });

                  console.log('[WhaleStore] After filtering:', productsWithStock.length, 'products with stock');

                  var transformed = productsWithStock.map(function(p) {
                    var inv = Array.isArray(p.inventory) ? p.inventory[0] : (p.inventory || {});
                    var schema = p.pricing_schema || {};
                    var tiers = schema.tiers || [];
                    return {
                      id: p.id, name: p.name, description: p.description, sku: p.sku,
                      price: p.price, regular_price: p.regular_price, sale_price: p.sale_price,
                      on_sale: p.on_sale, featured_image: p.featured_image,
                      custom_fields: p.custom_fields, pricing_data: p.pricing_data,
                      store_id: p.store_id,
                      primary_category_id: p.primary_category_id,
                      pricing_schema_id: p.pricing_schema_id,
                      category_name: p.primary_category?.name,
                      status: p.status,
                      pricing_schema: schema,
                      tiers: tiers,
                      location_quantity: inv.total_quantity || 0,
                      location_available: inv.available_quantity || 0,
                      location_reserved: (inv.total_quantity || 0) - (inv.available_quantity || 0),
                      in_stock: true,
                      strain_type: p.custom_fields?.strain_type,
                      thca_percentage: p.custom_fields?.thca_percentage,
                      thc_percentage: p.custom_fields?.thc_percentage
                    };
                  });

                  if (mounted) { setData(transformed); setLoading(false); }
                } catch (e) {
                  console.error('[WhaleStore] Error:', e);
                  if (mounted) { setData([]); setLoading(false); }
                }
              }

              fetchProducts();
              var interval = setInterval(fetchProducts, POLL_INTERVAL);
              return function() { mounted = false; clearInterval(interval); };
            }, []);

            return { data: data, loading: loading };
          }

          function useCollectionTheme() {
            const React = window.React;
            const [theme, setTheme] = React.useState(null);
            const [loading, setLoading] = React.useState(true);

            React.useEffect(function() {
              let mounted = true;

              async function fetchTheme() {
                if (!CREATION_ID) { setLoading(false); return; }
                try {
                  var itemsUrl = SUPABASE_URL + '/rest/v1/creation_collection_items?select=collection_id&creation_id=eq.' + CREATION_ID + '&limit=1';
                  var itemsResp = await fetch(itemsUrl, { headers: { 'apikey': SUPABASE_KEY, 'Authorization': 'Bearer ' + SUPABASE_KEY } });
                  var items = await itemsResp.json();
                  if (!items || items.length === 0) { if (mounted) setLoading(false); return; }

                  var collUrl = SUPABASE_URL + '/rest/v1/creation_collections?select=design_system&id=eq.' + items[0].collection_id;
                  var collResp = await fetch(collUrl, { headers: { 'apikey': SUPABASE_KEY, 'Authorization': 'Bearer ' + SUPABASE_KEY } });
                  var colls = await collResp.json();

                  if (mounted && colls && colls.length > 0) {
                    setTheme(colls[0].design_system || {});
                    setLoading(false);
                  }
                } catch (e) {
                  console.error('[WhaleStore] collectionTheme error:', e);
                  if (mounted) setLoading(false);
                }
              }

              fetchTheme();
              return function() { mounted = false; };
            }, []);

            return {
              loading: loading, theme: theme,
              colors: theme?.colors || {}, typography: theme?.typography || {},
              primary: theme?.colors?.primary || '#000000',
              secondary: theme?.colors?.secondary || '#111111',
              text: theme?.colors?.text || '#ffffff',
              muted: theme?.colors?.muted || '#666666',
              headingFont: theme?.typography?.heading_font || 'Playfair Display',
              bodyFont: theme?.typography?.body_font || 'Inter'
            };
          }

          window.useStore = {
            store: useStoreInfo,
            collectionTheme: useCollectionTheme,
            productsWithInventory: useProductsWithInventory,
            products: function(f) { return useQuery('products', f); },
            categories: function() { return useQuery('categories'); },
            locations: function() { return useQuery('locations'); },
            query: function(t, f) { return useQuery(t, f); },
            context: { storeId: STORE_ID, locationId: LOCATION_ID }
          };

          window.WhaleStore = window.useStore;
          console.log('[WhaleStore] Ready', { store: STORE_ID, location: LOCATION_ID });
        })(window);
        """
    }
}

// MARK: - Creation HTML WebView

struct CreationHTMLWebView: UIViewRepresentable {
    let html: String
    @Binding var isLoading: Bool
    @Binding var loadError: String?

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> WKWebView {
        print("🪟 CreationHTMLWebView: Creating WKWebView")
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        // Enable JavaScript
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        config.defaultWebpagePreferences = prefs

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = true
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.scrollView.contentInsetAdjustmentBehavior = .never  // Edge-to-edge
        webView.navigationDelegate = context.coordinator

        #if DEBUG
        if #available(iOS 16.4, *) {
            webView.isInspectable = true
        }
        #endif

        // Load HTML with unpkg.com base URL for better CORS handling
        print("🪟 CreationHTMLWebView: Loading HTML (\(html.count) chars)")
        webView.loadHTMLString(html, baseURL: URL(string: "https://unpkg.com"))

        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        // Don't update - HTML is loaded once
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        let parent: CreationHTMLWebView

        init(parent: CreationHTMLWebView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            print("🪟 CreationHTMLWebView: Started loading")
            DispatchQueue.main.async {
                self.parent.isLoading = true
                self.parent.loadError = nil
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            print("🪟 CreationHTMLWebView: Finished loading")
            DispatchQueue.main.async {
                self.parent.isLoading = false
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            print("🪟 CreationHTMLWebView: Failed - \(error.localizedDescription)")
            DispatchQueue.main.async {
                self.parent.isLoading = false
                self.parent.loadError = error.localizedDescription
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            print("🪟 CreationHTMLWebView: Provisional failed - \(error.localizedDescription)")
            DispatchQueue.main.async {
                self.parent.isLoading = false
                self.parent.loadError = error.localizedDescription
            }
        }
    }
}

// MARK: - Stage Window WebView (for URLs)

struct StageWindowWebView: View {
    let urlString: String
    @State private var isLoading = true
    @State private var loadError: String?

    var body: some View {
        ZStack {
            StageWindowWebViewRepresentable(
                urlString: urlString,
                isLoading: $isLoading,
                loadError: $loadError
            )

            if isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(.white)
                    Text("Loading...")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(urlString)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(2)
                        .padding(.horizontal)
                }
            }

            if let error = loadError {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.orange)
                    Text("Failed to load")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }
        }
        .background(Color.black)
    }
}

struct StageWindowWebViewRepresentable: UIViewRepresentable {
    let urlString: String
    @Binding var isLoading: Bool
    @Binding var loadError: String?

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> WKWebView {
        print("🪟 StageWindowWebView: Creating WKWebView for \(urlString)")
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.navigationDelegate = context.coordinator

        if let url = URL(string: urlString) {
            print("🪟 StageWindowWebView: Loading URL \(url)")
            webView.load(URLRequest(url: url))
        } else {
            print("🪟 StageWindowWebView: Invalid URL!")
            DispatchQueue.main.async {
                self.loadError = "Invalid URL"
                self.isLoading = false
            }
        }

        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        // Only reload if URL changed
        if uiView.url?.absoluteString != urlString, let url = URL(string: urlString) {
            print("🪟 StageWindowWebView: URL changed, reloading")
            uiView.load(URLRequest(url: url))
        }
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        let parent: StageWindowWebViewRepresentable

        init(parent: StageWindowWebViewRepresentable) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            print("🪟 StageWindowWebView: Started loading")
            DispatchQueue.main.async {
                self.parent.isLoading = true
                self.parent.loadError = nil
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            print("🪟 StageWindowWebView: Finished loading successfully")
            DispatchQueue.main.async {
                self.parent.isLoading = false
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            print("🪟 StageWindowWebView: Failed to load - \(error.localizedDescription)")
            DispatchQueue.main.async {
                self.parent.isLoading = false
                self.parent.loadError = error.localizedDescription
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            print("🪟 StageWindowWebView: Failed provisional navigation - \(error.localizedDescription)")
            DispatchQueue.main.async {
                self.parent.isLoading = false
                self.parent.loadError = error.localizedDescription
            }
        }
    }
}

// MARK: - Stage Manager Background

struct StageManagerBackground: View {
    @ObservedObject var store = StageManagerStore.shared

    var body: some View {
        ZStack {
            // Base gradient
            MeshGradient(
                width: 3,
                height: 3,
                points: [
                    [0, 0], [0.5, 0], [1, 0],
                    [0, 0.5], [0.5, 0.5], [1, 0.5],
                    [0, 1], [0.5, 1], [1, 1]
                ],
                colors: [
                    Color(red: 0.30, green: 0.12, blue: 0.40),
                    Color(red: 0.40, green: 0.20, blue: 0.50),
                    Color(red: 0.25, green: 0.12, blue: 0.45),
                    Color(red: 0.50, green: 0.22, blue: 0.42),
                    Color(red: 0.40, green: 0.30, blue: 0.50),
                    Color(red: 0.30, green: 0.22, blue: 0.50),
                    Color(red: 0.55, green: 0.35, blue: 0.42),
                    Color(red: 0.45, green: 0.35, blue: 0.50),
                    Color(red: 0.40, green: 0.30, blue: 0.45)
                ]
            )
            .blur(radius: 100)
            .saturation(1.5)

        }
        .ignoresSafeArea()
        .onTapGesture {
            Haptics.light()
            store.hide()
        }
    }
}

// MARK: - Stage Manager Overlay

struct StageManagerOverlay: View {
    let geo: GeometryProxy
    let mainWindowScale: CGFloat
    @ObservedObject var store = StageManagerStore.shared

    private var cardWidth: CGFloat { geo.size.width * mainWindowScale }
    private var cardHeight: CGFloat { geo.size.height * mainWindowScale }

    var body: some View {
        VStack {
            // Window labels at appropriate positions
            GeometryReader { _ in
                ForEach(Array(store.windows.enumerated()), id: \.element.id) { index, window in
                    let offset = windowOffset(index: index)

                    VStack {
                        Spacer()
                            .frame(height: geo.size.height * 0.5 + cardHeight * 0.5 + 16)

                        Text(window.name)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                    .offset(x: offset)
                }
            }

            Spacer()
        }
    }

    private func windowOffset(index: Int) -> CGFloat {
        let totalWindows = store.windows.count
        let spacing: CGFloat = 40
        let totalWidth = CGFloat(totalWindows) * cardWidth + CGFloat(totalWindows - 1) * spacing
        let startX = -totalWidth / 2 + cardWidth / 2
        return startX + CGFloat(index) * (cardWidth + spacing)
    }
}

// MARK: - Window-level Pinch Gesture

struct WindowPinchGesture: ViewModifier {
    var onChanged: (CGFloat) -> Void
    var onEnded: (CGFloat) -> Void

    func body(content: Content) -> some View {
        content
            .overlay(
                GestureInstallerView(onChanged: onChanged, onEnded: onEnded)
                    .frame(width: 0, height: 0)
            )
    }
}

struct GestureInstallerView: UIViewControllerRepresentable {
    var onChanged: (CGFloat) -> Void
    var onEnded: (CGFloat) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onChanged: onChanged, onEnded: onEnded)
    }

    func makeUIViewController(context: Context) -> GestureInstallerController {
        let controller = GestureInstallerController()
        controller.coordinator = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: GestureInstallerController, context: Context) {
        context.coordinator.onChanged = onChanged
        context.coordinator.onEnded = onEnded
    }

    class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onChanged: (CGFloat) -> Void
        var onEnded: (CGFloat) -> Void
        weak var gestureRecognizer: UIPinchGestureRecognizer?

        init(onChanged: @escaping (CGFloat) -> Void, onEnded: @escaping (CGFloat) -> Void) {
            self.onChanged = onChanged
            self.onEnded = onEnded
        }

        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            switch gesture.state {
            case .began, .changed:
                onChanged(gesture.scale)
            case .ended, .cancelled:
                onEnded(gesture.scale)
            default:
                break
            }
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            return true
        }
    }
}

class GestureInstallerController: UIViewController {
    var coordinator: GestureInstallerView.Coordinator?
    private var pinchGesture: UIPinchGestureRecognizer?

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        installGestureOnWindow()
    }

    private func installGestureOnWindow() {
        guard let window = view.window, pinchGesture == nil else { return }

        let pinch = UIPinchGestureRecognizer(target: coordinator, action: #selector(GestureInstallerView.Coordinator.handlePinch(_:)))
        pinch.delegate = coordinator
        window.addGestureRecognizer(pinch)
        pinchGesture = pinch
        coordinator?.gestureRecognizer = pinch
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if let gesture = pinchGesture {
            view.window?.removeGestureRecognizer(gesture)
            pinchGesture = nil
        }
    }
}
