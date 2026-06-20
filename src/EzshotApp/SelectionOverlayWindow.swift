import AppKit

final class SelectionOverlayWindow: NSPanel {
    init(
        screen: NSScreen,
        onComplete: @escaping (CGRect) -> Void,
        onCancel: @escaping () -> Void
    ) {
        let view = SelectionOverlayView(
            screenFrame: screen.frame,
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
        (contentView as? SelectionOverlayView)?.endSelectionCursor()
    }

    func beginSelectionCursor() {
        (contentView as? SelectionOverlayView)?.beginSelectionCursor()
    }

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        true
    }
}

private final class SelectionOverlayView: NSView {
    private let screenFrame: CGRect
    private let onComplete: (CGRect) -> Void
    private let onCancel: () -> Void
    private var startPoint: CGPoint?
    private var currentPoint: CGPoint?
    private var hoverPoint: CGPoint?
    private var didPushCursor = false
    private var didHideCursor = false

    init(
        screenFrame: CGRect,
        onComplete: @escaping (CGRect) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.screenFrame = screenFrame
        self.onComplete = onComplete
        self.onCancel = onCancel
        super.init(frame: CGRect(origin: .zero, size: screenFrame.size))
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.28).cgColor
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
            options: [.activeAlways, .mouseEnteredAndExited, .mouseMoved, .inVisibleRect],
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
        NSCursor.crosshair.set()
        NSCursor.hide()
        didPushCursor = true
        didHideCursor = true
    }

    func endSelectionCursor() {
        guard didPushCursor else {
            return
        }

        NSCursor.pop()
        didPushCursor = false
        if didHideCursor {
            NSCursor.unhide()
            didHideCursor = false
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel()
        }
    }

    override func keyUp(with event: NSEvent) {}

    override func flagsChanged(with event: NSEvent) {}

    override func mouseDown(with event: NSEvent) {
        NSCursor.crosshair.set()
        startPoint = convert(event.locationInWindow, from: nil)
        currentPoint = startPoint
        hoverPoint = startPoint
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        NSCursor.crosshair.set()
        currentPoint = convert(event.locationInWindow, from: nil)
        hoverPoint = currentPoint
        needsDisplay = true
    }

    override func mouseMoved(with event: NSEvent) {
        NSCursor.crosshair.set()
        hoverPoint = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseEntered(with event: NSEvent) {
        NSCursor.crosshair.set()
        hoverPoint = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        hoverPoint = nil
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        hoverPoint = currentPoint
        guard let selectionRect else {
            onCancel()
            return
        }

        if selectionRect.width < 4 || selectionRect.height < 4 {
            onCancel()
            return
        }

        let globalRect = selectionRect.offsetBy(dx: screenFrame.minX, dy: screenFrame.minY)
        DispatchQueue.main.async { [onComplete] in
            onComplete(globalRect)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawGuideLines()
        drawCursorCrosshair()

        guard let selectionRect else {
            return
        }

        NSColor.clear.setFill()
        selectionRect.fill(using: .copy)

        NSColor.controlAccentColor.setStroke()
        let border = NSBezierPath(rect: selectionRect)
        border.lineWidth = 2
        border.stroke()
    }

    private func drawGuideLines() {
        guard let point = hoverPoint else {
            return
        }

        let darkPath = NSBezierPath()
        darkPath.move(to: NSPoint(x: point.x, y: bounds.minY))
        darkPath.line(to: NSPoint(x: point.x, y: bounds.maxY))
        darkPath.move(to: NSPoint(x: bounds.minX, y: point.y))
        darkPath.line(to: NSPoint(x: bounds.maxX, y: point.y))
        NSColor.black.withAlphaComponent(0.62).setStroke()
        darkPath.lineWidth = 3
        darkPath.stroke()

        let lightPath = NSBezierPath()
        lightPath.move(to: NSPoint(x: point.x, y: bounds.minY))
        lightPath.line(to: NSPoint(x: point.x, y: bounds.maxY))
        lightPath.move(to: NSPoint(x: bounds.minX, y: point.y))
        lightPath.line(to: NSPoint(x: bounds.maxX, y: point.y))
        NSColor.white.withAlphaComponent(0.88).setStroke()
        lightPath.lineWidth = 1
        lightPath.stroke()
    }

    private func drawCursorCrosshair() {
        guard let point = hoverPoint else {
            return
        }

        let length: CGFloat = 13
        let gap: CGFloat = 3

        let darkPath = NSBezierPath()
        darkPath.move(to: NSPoint(x: point.x - length, y: point.y))
        darkPath.line(to: NSPoint(x: point.x - gap, y: point.y))
        darkPath.move(to: NSPoint(x: point.x + gap, y: point.y))
        darkPath.line(to: NSPoint(x: point.x + length, y: point.y))
        darkPath.move(to: NSPoint(x: point.x, y: point.y - length))
        darkPath.line(to: NSPoint(x: point.x, y: point.y - gap))
        darkPath.move(to: NSPoint(x: point.x, y: point.y + gap))
        darkPath.line(to: NSPoint(x: point.x, y: point.y + length))
        NSColor.black.withAlphaComponent(0.78).setStroke()
        darkPath.lineWidth = 3
        darkPath.stroke()

        let lightPath = darkPath.copy() as? NSBezierPath ?? NSBezierPath()
        NSColor.white.setStroke()
        lightPath.lineWidth = 1
        lightPath.stroke()
    }

    private var selectionRect: CGRect? {
        guard
            let startPoint,
            let currentPoint
        else {
            return nil
        }

        return CGRect(
            x: min(startPoint.x, currentPoint.x),
            y: min(startPoint.y, currentPoint.y),
            width: abs(startPoint.x - currentPoint.x),
            height: abs(startPoint.y - currentPoint.y)
        )
    }
}
