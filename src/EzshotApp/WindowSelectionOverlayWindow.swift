import AppKit
import CoreGraphics

struct CapturableWindow {
    let id: CGWindowID
    let bounds: CGRect
    let ownerName: String
}

final class WindowSelectionOverlayWindow: NSPanel {
    init(
        screen: NSScreen,
        windows: [CapturableWindow],
        onComplete: @escaping (CapturableWindow) -> Void,
        onCancel: @escaping () -> Void
    ) {
        let view = WindowSelectionOverlayView(
            screenFrame: screen.frame,
            windows: windows,
            onComplete: onComplete,
            onCancel: onCancel
        )

        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        isFloatingPanel = true
        level = .screenSaver
        hasShadow = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        becomesKeyOnlyIfNeeded = true
        contentView = view
    }

    func endSelectionCursor() {
        (contentView as? WindowSelectionOverlayView)?.endSelectionCursor()
    }

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        true
    }
}

private final class WindowSelectionOverlayView: NSView {
    private let screenFrame: CGRect
    private let windows: [CapturableWindow]
    private let onComplete: (CapturableWindow) -> Void
    private let onCancel: () -> Void
    private var hoveredWindow: CapturableWindow?
    private var didPushCursor = false

    init(
        screenFrame: CGRect,
        windows: [CapturableWindow],
        onComplete: @escaping (CapturableWindow) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.screenFrame = screenFrame
        self.windows = windows
        self.onComplete = onComplete
        self.onCancel = onCancel
        super.init(frame: CGRect(origin: .zero, size: screenFrame.size))
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.08).cgColor
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseMoved, .inVisibleRect],
            owner: self
        ))
        beginSelectionCursor()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    func beginSelectionCursor() {
        guard !didPushCursor else {
            NSCursor.crosshair.set()
            return
        }

        NSCursor.crosshair.push()
        didPushCursor = true
    }

    func endSelectionCursor() {
        guard didPushCursor else {
            return
        }

        NSCursor.pop()
        didPushCursor = false
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel()
        }
    }

    override func keyUp(with event: NSEvent) {}

    override func flagsChanged(with event: NSEvent) {}

    override func mouseMoved(with event: NSEvent) {
        NSCursor.crosshair.set()
        hoveredWindow = window(at: convert(event.locationInWindow, from: nil))
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        NSCursor.crosshair.set()
        if let target = window(at: convert(event.locationInWindow, from: nil)) {
            onComplete(target)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let hoveredWindow else {
            return
        }

        let rect = localRect(for: hoveredWindow.bounds)
        NSColor.clear.setFill()
        rect.fill(using: .copy)
        NSColor.controlAccentColor.withAlphaComponent(0.20).setFill()
        rect.fill()
        NSColor.controlAccentColor.setStroke()
        let path = NSBezierPath(roundedRect: rect.insetBy(dx: 2, dy: 2), xRadius: 6, yRadius: 6)
        path.lineWidth = 3
        path.stroke()
    }

    private func window(at point: CGPoint) -> CapturableWindow? {
        let globalPoint = CGPoint(x: point.x + screenFrame.minX, y: screenFrame.maxY - point.y)
        return windows.first { window in
            window.bounds.contains(globalPoint)
        }
    }

    private func localRect(for globalRect: CGRect) -> CGRect {
        CGRect(
            x: globalRect.minX - screenFrame.minX,
            y: screenFrame.maxY - globalRect.maxY,
            width: globalRect.width,
            height: globalRect.height
        )
    }
}
