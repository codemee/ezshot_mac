import AppKit

@MainActor
final class CountdownOverlayController {
    private let seconds: Double
    private let onComplete: @MainActor () -> Void
    private var windows: [CountdownOverlayWindow] = []
    private var timer: Timer?
    private var startTime: Date?

    init(seconds: Double, onComplete: @escaping @MainActor () -> Void) {
        self.seconds = max(0, seconds)
        self.onComplete = onComplete
    }

    func start() {
        cancel()

        let initialValue = max(Int(ceil(seconds)), 1)
        windows = NSScreen.screens.map { screen in
            CountdownOverlayWindow(screen: screen, value: initialValue)
        }
        windows.forEach { $0.orderFrontRegardless() }
        startTime = Date()

        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
        timer?.tolerance = 0.03
        tick()
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
        windows.forEach { $0.close() }
        windows.removeAll()
        startTime = nil
    }

    private func tick() {
        guard let startTime else {
            return
        }

        let elapsed = Date().timeIntervalSince(startTime)
        let remaining = seconds - elapsed
        guard remaining > 0 else {
            finish()
            return
        }

        let value = max(Int(ceil(remaining)), 1)
        windows.forEach { $0.update(value: value) }
    }

    private func finish() {
        timer?.invalidate()
        timer = nil
        windows.forEach { $0.orderOut(nil) }

        // Keep the countdown itself out of the screenshot.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [windows, onComplete] in
            windows.forEach { $0.close() }
            onComplete()
        }
        windows.removeAll()
        startTime = nil
    }
}

private final class CountdownOverlayWindow: NSPanel {
    private let countdownView: CountdownOverlayView

    init(screen: NSScreen, value: Int) {
        countdownView = CountdownOverlayView(value: value)

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
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        contentView = countdownView
    }

    func update(value: Int) {
        countdownView.value = value
    }
}

private final class CountdownOverlayView: NSView {
    var value: Int {
        didSet {
            needsDisplay = true
        }
    }

    init(value: Int) {
        self.value = value
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let diameter: CGFloat = 118
        let circleRect = NSRect(
            x: bounds.midX - diameter / 2,
            y: bounds.midY - diameter / 2,
            width: diameter,
            height: diameter
        )

        NSGraphicsContext.current?.cgContext.setShadow(
            offset: CGSize(width: 0, height: -4),
            blur: 14,
            color: NSColor.black.withAlphaComponent(0.28).cgColor
        )

        NSColor.black.withAlphaComponent(0.34).setFill()
        NSBezierPath(ovalIn: circleRect).fill()

        NSGraphicsContext.current?.cgContext.setShadow(offset: .zero, blur: 0)
        NSColor.white.withAlphaComponent(0.68).setStroke()
        let ring = NSBezierPath(ovalIn: circleRect.insetBy(dx: 3, dy: 3))
        ring.lineWidth = 2
        ring.stroke()

        let text = "\(value)" as NSString
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: value >= 10 ? 50 : 64, weight: .bold),
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraphStyle
        ]
        let textSize = text.size(withAttributes: attributes)
        let textRect = NSRect(
            x: circleRect.midX - textSize.width / 2,
            y: circleRect.midY - textSize.height / 2 - 2,
            width: textSize.width,
            height: textSize.height
        )

        text.draw(in: textRect, withAttributes: attributes)
    }
}
