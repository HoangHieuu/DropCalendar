import AppKit
import ImageIO
import Observation
import SwiftUI
import UniformTypeIdentifiers

struct NotchPanelLayout {
    static let collapsedWidth: CGFloat = 184
    static let expandedSize = CGSize(width: 372, height: 148)
    static let windowLevel = NSWindow.Level.mainMenu

    static func size(topInset: CGFloat, isExpanded: Bool) -> CGSize {
        guard !isExpanded else { return expandedSize }
        return CGSize(
            width: collapsedWidth,
            height: max(34, min(topInset, 44))
        )
    }

    static func frame(
        in screenFrame: CGRect,
        topInset: CGFloat,
        isExpanded: Bool
    ) -> CGRect {
        let panelSize = size(topInset: topInset, isExpanded: isExpanded)
        return CGRect(
            x: screenFrame.midX - panelSize.width / 2,
            y: screenFrame.maxY - panelSize.height,
            width: panelSize.width,
            height: panelSize.height
        )
    }
}

struct NotchHoverExitPolicy {
    static let edgeTolerance: CGFloat = 6

    static func containsPointer(_ location: CGPoint, in panelFrame: CGRect) -> Bool {
        panelFrame
            .insetBy(dx: -edgeTolerance, dy: -edgeTolerance)
            .contains(location)
    }
}

enum NotchDropSelectionError: Error, Equatable {
    case empty
    case unsupported
}

struct NotchDropSelection: Equatable {
    enum Payload: Sendable, Equatable {
        case file(URL)
        case image(ClipboardImage)
    }

    let payload: Payload
    let ignoredItemCount: Int

    private static let supportedExtensions = Set(["png", "jpg", "jpeg", "heic"])

    static func select(from urls: [URL]) throws -> NotchDropSelection {
        guard !urls.isEmpty else { throw NotchDropSelectionError.empty }
        guard let selectedURL = urls.first(where: isSupportedImage) else {
            throw NotchDropSelectionError.unsupported
        }
        return NotchDropSelection(
            payload: .file(selectedURL),
            ignoredItemCount: max(0, urls.count - 1)
        )
    }

    static func isSupportedImage(_ url: URL) -> Bool {
        url.isFileURL && supportedExtensions.contains(url.pathExtension.lowercased())
    }
}

@MainActor
struct NotchDropProviderLoader {
    static let supportedTypeIdentifiers = [
        UTType.fileURL.identifier,
        UTType.png.identifier,
        UTType.jpeg.identifier,
        UTType.heic.identifier,
        UTType.tiff.identifier,
        UTType.image.identifier
    ]

    private let now: () -> Date

    init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    func select(from providers: [NSItemProvider]) async throws -> NotchDropSelection {
        guard !providers.isEmpty else { throw NotchDropSelectionError.empty }

        for provider in providers {
            if let payload = await loadSupportedPayload(from: provider) {
                return NotchDropSelection(
                    payload: payload,
                    ignoredItemCount: max(0, providers.count - 1)
                )
            }
        }
        throw NotchDropSelectionError.unsupported
    }

    private func loadSupportedPayload(
        from provider: NSItemProvider
    ) async -> NotchDropSelection.Payload? {
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier),
           let image = try? await loadFileURLImage(from: provider) {
            return .image(image)
        }

        let dataTypes: [(type: UTType, fileExtension: String)] = [
            (.png, "png"),
            (.jpeg, "jpg"),
            (.heic, "heic"),
            (.tiff, "tiff")
        ]
        for candidate in dataTypes where provider.hasItemConformingToTypeIdentifier(
            candidate.type.identifier
        ) {
            guard let data = try? await loadData(
                from: provider,
                typeIdentifier: candidate.type.identifier
            ) else { continue }

            if candidate.type == .tiff {
                guard let pngData = convertTIFFToPNG(data) else { continue }
                return .image(ClipboardImage(
                    data: pngData,
                    fileName: "Dropped Screenshot.png",
                    capturedAt: now()
                ))
            }
            return .image(ClipboardImage(
                data: data,
                fileName: "Dropped Screenshot.\(candidate.fileExtension)",
                capturedAt: now()
            ))
        }

        guard provider.hasItemConformingToTypeIdentifier(UTType.image.identifier),
              let image = try? await loadTemporaryImage(from: provider) else {
            return nil
        }
        return .image(image)
    }

    private func loadFileURLImage(from provider: NSItemProvider) async throws -> ClipboardImage {
        let item: NSSecureCoding = try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(
                forTypeIdentifier: UTType.fileURL.identifier,
                options: nil
            ) { item, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let item {
                    continuation.resume(returning: item)
                } else {
                    continuation.resume(throwing: NotchDropSelectionError.unsupported)
                }
            }
        }

        let url: URL?
        if let itemURL = item as? URL {
            url = itemURL
        } else if let itemURL = item as? NSURL {
            url = itemURL as URL
        } else if let string = item as? String {
            url = URL(string: string)
        } else if let data = item as? Data {
            url = URL(dataRepresentation: data, relativeTo: nil)
        } else {
            url = nil
        }
        guard let url, url.isFileURL else {
            throw NotchDropSelectionError.unsupported
        }

        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess { url.stopAccessingSecurityScopedResource() }
        }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        let capturedAt = values?.contentModificationDate ?? now()

        if NotchDropSelection.isSupportedImage(url) {
            return ClipboardImage(
                data: data,
                fileName: url.lastPathComponent,
                capturedAt: capturedAt
            )
        }
        guard let normalized = Self.normalizedImage(data: data) else {
            throw NotchDropSelectionError.unsupported
        }
        return ClipboardImage(
            data: normalized.data,
            fileName: "Dropped Screenshot.\(normalized.fileExtension)",
            capturedAt: capturedAt
        )
    }

    private func loadData(
        from provider: NSItemProvider,
        typeIdentifier: String
    ) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: NotchDropSelectionError.unsupported)
                }
            }
        }
    }

    private func loadTemporaryImage(
        from provider: NSItemProvider
    ) async throws -> ClipboardImage {
        let capturedAt = now()
        return try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<ClipboardImage, Error>) in
            provider.loadFileRepresentation(
                forTypeIdentifier: UTType.image.identifier
            ) { url, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let url, let data = try? Data(contentsOf: url, options: .mappedIfSafe),
                      let normalized = Self.normalizedImage(data: data) else {
                    continuation.resume(throwing: NotchDropSelectionError.unsupported)
                    return
                }
                continuation.resume(returning: ClipboardImage(
                    data: normalized.data,
                    fileName: "Dropped Screenshot.\(normalized.fileExtension)",
                    capturedAt: capturedAt
                ))
            }
        }
    }

    private func convertTIFFToPNG(_ data: Data) -> Data? {
        guard !data.isEmpty, let bitmap = NSBitmapImageRep(data: data) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }

    nonisolated private static func normalizedImage(
        data: Data
    ) -> (data: Data, fileExtension: String)? {
        guard !data.isEmpty,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let typeIdentifier = CGImageSourceGetType(source) as String?,
              let type = UTType(typeIdentifier) else {
            return nil
        }
        if type.conforms(to: .png) { return (data, "png") }
        if type.conforms(to: .jpeg) { return (data, "jpg") }
        if type.conforms(to: .heic) { return (data, "heic") }
        if type.conforms(to: .tiff),
           let bitmap = NSBitmapImageRep(data: data),
           let pngData = bitmap.representation(using: .png, properties: [:]) {
            return (pngData, "png")
        }
        return nil
    }
}

@MainActor
struct NotchDropImporter {
    let model: SnapCalModel

    func importSelection(_ selection: NotchDropSelection) async {
        switch selection.payload {
        case .file(let url):
            let didAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didAccess { url.stopAccessingSecurityScopedResource() }
            }
            await model.importScreenshot(from: url)
        case .image(let image):
            await model.importInMemoryImage(image)
        }
    }
}

@MainActor
@Observable
private final class NotchDropPresentation {
    var message: String?
    var isPinned = false
    var isHovering = false
}

private struct NotchDropZoneView: View {
    let model: SnapCalModel
    let presentation: NotchDropPresentation
    let onHoverChanged: (Bool) -> Void
    let onExpansionChanged: (Bool) -> Void
    let onDrop: ([NSItemProvider]) -> Void

    @State private var isDropTargeted = false

    private var isExpanded: Bool {
        presentation.isHovering || isDropTargeted || presentation.isPinned
    }

    private var accent: Color {
        isDropTargeted ? .green : .accentColor
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: isExpanded ? 24 : 15, style: .continuous)
                .fill(.black.opacity(0.96))
                .overlay {
                    RoundedRectangle(cornerRadius: isExpanded ? 24 : 15, style: .continuous)
                        .stroke(accent.opacity(isDropTargeted ? 0.95 : 0.28), lineWidth: isDropTargeted ? 2 : 1)
                }

            if isExpanded {
                expandedContent
                    .transition(.opacity.combined(with: .scale(scale: 0.94)))
            } else {
                collapsedContent
                    .transition(.opacity)
            }
        }
        .contentShape(Rectangle())
        .onHover(perform: onHoverChanged)
        .onDrop(
            of: NotchDropProviderLoader.supportedTypeIdentifiers,
            isTargeted: $isDropTargeted
        ) { providers in
            onDrop(providers)
            return true
        }
        .onChange(of: isExpanded) { _, newValue in
            onExpansionChanged(newValue)
        }
        .animation(.snappy(duration: 0.24), value: isExpanded)
        .animation(.easeOut(duration: 0.16), value: isDropTargeted)
        .shadow(color: .black.opacity(0.34), radius: isExpanded ? 22 : 8, y: 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("SnapCal screenshot drop zone")
        .accessibilityHint("Drop one PNG, JPEG, or HEIC event screenshot to create a reviewable draft.")
        .accessibilityIdentifier("notchDropZone")
    }

    private var collapsedContent: some View {
        HStack(spacing: 8) {
            Image(systemName: "calendar.badge.plus")
                .foregroundStyle(.white)
            Text("SnapCal")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white.opacity(0.52))
        }
        .padding(.horizontal, 16)
    }

    private var expandedContent: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(accent.opacity(0.2))
                    .frame(width: 66, height: 66)
                Image(systemName: isDropTargeted ? "arrow.down.circle.fill" : "photo.badge.plus")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(accent)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(isDropTargeted ? "Release to create a draft" : "Drop event screenshot")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)

                Text(presentation.message ?? "PNG, JPG, JPEG, or HEIC • review before creating")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.66))
                    .lineLimit(2)

                Text(model.extractionMode.title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(accent.opacity(0.14), in: Capsule())
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 22)
        .padding(.top, 14)
        .padding(.bottom, 18)
        .scaleEffect(isDropTargeted ? 1.02 : 1)
    }
}

@MainActor
final class NotchPanelController: NSWindowController {
    private let model: SnapCalModel
    private let reopenMainWindow: () -> Void
    private let presentation = NotchDropPresentation()
    private var isExpanded = false
    private var screenObserver: NSObjectProtocol?
    private var statusTask: Task<Void, Never>?
    private var hoverExitTask: Task<Void, Never>?
    private var isLoadingDrop = false

    private static let hoverExitDelayNanoseconds: UInt64 = 140_000_000
    private static let hoverExitPollNanoseconds: UInt64 = 80_000_000

    init(model: SnapCalModel, reopenMainWindow: @escaping () -> Void) {
        self.model = model
        self.reopenMainWindow = reopenMainWindow
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init(window: panel)

        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        // Keep the drop surface above normal application windows without
        // covering app-owned or system status items at `.statusBar` level.
        panel.level = NotchPanelLayout.windowLevel
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle
        ]

        panel.contentView = NSHostingView(rootView: NotchDropZoneView(
            model: model,
            presentation: presentation,
            onHoverChanged: { [weak self] in self?.handleHoverChanged($0) },
            onExpansionChanged: { [weak self] in self?.setExpanded($0, animated: true) },
            onDrop: { [weak self] in self?.handleDrop(providers: $0) }
        ))

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reposition(animated: false) }
        }
        reposition(animated: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        statusTask?.cancel()
        hoverExitTask?.cancel()
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
    }

    func present() {
        reposition(animated: false)
        window?.orderFrontRegardless()
    }

    private func setExpanded(_ expanded: Bool, animated: Bool) {
        guard isExpanded != expanded else { return }
        isExpanded = expanded
        reposition(animated: animated)
    }

    private func handleHoverChanged(_ isHovering: Bool) {
        hoverExitTask?.cancel()

        guard !isHovering else {
            presentation.isHovering = true
            return
        }

        hoverExitTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: Self.hoverExitDelayNanoseconds)
                guard let self else { return }

                while self.isPointerOverPanel {
                    try await Task.sleep(nanoseconds: Self.hoverExitPollNanoseconds)
                }
                presentation.isHovering = false
            } catch {
                return
            }
        }
    }

    private var isPointerOverPanel: Bool {
        guard let panelFrame = window?.frame else { return false }
        return NotchHoverExitPolicy.containsPointer(
            NSEvent.mouseLocation,
            in: panelFrame
        )
    }

    private func reposition(animated: Bool) {
        guard let panel = window,
              let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let targetFrame = NotchPanelLayout.frame(
            in: screen.frame,
            topInset: screen.safeAreaInsets.top,
            isExpanded: isExpanded
        )
        guard animated else {
            panel.setFrame(targetFrame, display: true)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(targetFrame, display: true)
        }
    }

    private func handleDrop(providers: [NSItemProvider]) {
        if model.isCalendarOperationInProgress {
            showStatus("Finish the current Calendar action before importing another screenshot.", duration: 2.5)
            return
        }
        if case .processing = model.phase {
            showStatus("SnapCal is already processing a screenshot.", duration: 2)
            return
        }
        guard !isLoadingDrop else {
            showStatus("SnapCal is already reading a dropped screenshot.", duration: 2)
            return
        }

        isLoadingDrop = true
        Task { [weak self] in
            guard let self else { return }
            defer { isLoadingDrop = false }

            let selection: NotchDropSelection
            do {
                selection = try await NotchDropProviderLoader().select(from: providers)
            } catch {
                revealMainWindow()
                model.presentFailure(ImportIssue(
                    title: "Unsupported drop",
                    message: "Drop one PNG, JPG, JPEG, or HEIC screenshot."
                ))
                showStatus("That drop did not contain a supported image.", duration: 2.5)
                return
            }

            let message = selection.ignoredItemCount > 0
                ? "Using the first supported image • \(selection.ignoredItemCount) other item(s) ignored"
                : "Opening screenshot for review…"
            showStatus(message, duration: selection.ignoredItemCount > 0 ? 2.5 : 1)
            revealMainWindow()
            await NotchDropImporter(model: model).importSelection(selection)
        }
    }

    private func revealMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let mainWindow = NSApp.windows.first(where: { candidate in
            candidate !== window && !(candidate is NSPanel) && candidate.canBecomeMain
        }) {
            mainWindow.makeKeyAndOrderFront(nil)
            return
        }
        reopenMainWindow()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            NSApp.windows.first(where: { candidate in
                candidate !== self.window && !(candidate is NSPanel) && candidate.canBecomeMain
            })?.makeKeyAndOrderFront(nil)
        }
    }

    private func showStatus(_ message: String, duration: TimeInterval) {
        statusTask?.cancel()
        presentation.message = message
        presentation.isPinned = true
        statusTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.presentation.message = nil
            self?.presentation.isPinned = false
        }
    }
}

@MainActor
final class SnapCalAppDelegate: NSObject, NSApplicationDelegate {
    private var notchPanelController: NotchPanelController?

    func installNotchDropZone(
        model: SnapCalModel,
        reopenMainWindow: @escaping () -> Void
    ) {
        guard notchPanelController == nil else { return }
        let controller = NotchPanelController(
            model: model,
            reopenMainWindow: reopenMainWindow
        )
        notchPanelController = controller
        controller.present()
    }
}
