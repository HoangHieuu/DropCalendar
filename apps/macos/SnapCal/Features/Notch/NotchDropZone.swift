import AppKit
import Observation
import SwiftUI

struct NotchPanelLayout {
    static let collapsedWidth: CGFloat = 184
    static let expandedSize = CGSize(width: 372, height: 148)

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

enum NotchDropSelectionError: Error, Equatable {
    case empty
    case unsupported
}

struct NotchDropSelection: Equatable {
    let url: URL
    let ignoredItemCount: Int

    private static let supportedExtensions = Set(["png", "jpg", "jpeg", "heic"])

    static func select(from urls: [URL]) throws -> NotchDropSelection {
        guard !urls.isEmpty else { throw NotchDropSelectionError.empty }
        guard let selectedURL = urls.first(where: isSupportedImage) else {
            throw NotchDropSelectionError.unsupported
        }
        return NotchDropSelection(
            url: selectedURL,
            ignoredItemCount: max(0, urls.count - 1)
        )
    }

    private static func isSupportedImage(_ url: URL) -> Bool {
        url.isFileURL && supportedExtensions.contains(url.pathExtension.lowercased())
    }
}

@MainActor
struct NotchDropImporter {
    let model: SnapCalModel

    func importSelection(_ selection: NotchDropSelection) async {
        let didAccess = selection.url.startAccessingSecurityScopedResource()
        defer {
            if didAccess { selection.url.stopAccessingSecurityScopedResource() }
        }
        await model.importScreenshot(from: selection.url)
    }
}

@MainActor
@Observable
private final class NotchDropPresentation {
    var message: String?
    var isPinned = false
}

private struct NotchDropZoneView: View {
    let model: SnapCalModel
    let presentation: NotchDropPresentation
    let onExpansionChanged: (Bool) -> Void
    let onDrop: ([URL]) -> Void

    @State private var isHovering = false
    @State private var isDropTargeted = false

    private var isExpanded: Bool {
        isHovering || isDropTargeted || presentation.isPinned
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
        .onHover { isHovering = $0 }
        .dropDestination(
            for: URL.self,
            action: { urls, _ in
                onDrop(urls)
                return true
            },
            isTargeted: { isDropTargeted = $0 }
        )
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
        panel.level = .statusBar
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle
        ]

        panel.contentView = NSHostingView(rootView: NotchDropZoneView(
            model: model,
            presentation: presentation,
            onExpansionChanged: { [weak self] in self?.setExpanded($0, animated: true) },
            onDrop: { [weak self] in self?.handleDrop(urls: $0) }
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

    private func handleDrop(urls: [URL]) {
        if model.isCalendarOperationInProgress {
            showStatus("Finish the current Calendar action before importing another screenshot.", duration: 2.5)
            return
        }
        if case .processing = model.phase {
            showStatus("SnapCal is already processing a screenshot.", duration: 2)
            return
        }

        let selection: NotchDropSelection
        do {
            selection = try NotchDropSelection.select(from: urls)
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

        Task { [weak self] in
            guard let self else { return }
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
