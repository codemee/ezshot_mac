import AppKit
import EzshotCore

enum ScreenshotEditMode: String, CaseIterable {
    case line
    case arrow
    case rectangle
    case mosaic
    case text
}

@MainActor
final class ScreenshotEditorView: NSView {
    private let scrollView = NSScrollView()
    private let canvas: ScreenshotCanvasView

    var onDocumentChanged: (() -> Void)? {
        get { canvas.onDocumentChanged }
        set { canvas.onDocumentChanged = newValue }
    }

    var onModeChanged: ((ScreenshotEditMode) -> Void)? {
        get { canvas.onModeChanged }
        set { canvas.onModeChanged = newValue }
    }

    var mode: ScreenshotEditMode {
        get { canvas.mode }
        set { canvas.mode = newValue }
    }

    var canUndo: Bool {
        canvas.canUndo
    }

    var lineColor: NSColor {
        get { canvas.lineColor }
        set { canvas.lineColor = newValue }
    }

    var lineWidth: CGFloat {
        get { canvas.lineWidth }
        set { canvas.lineWidth = newValue }
    }

    var textValue: String {
        get { canvas.textValue }
        set { canvas.textValue = newValue }
    }

    var textFontName: String {
        get { canvas.textFontName }
        set { canvas.textFontName = newValue }
    }

    var textFontSize: CGFloat {
        get { canvas.textFontSize }
        set { canvas.textFontSize = newValue }
    }

    init(document: ScreenshotDocument) {
        self.canvas = ScreenshotCanvasView(document: document)
        super.init(frame: .zero)

        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .ezshotEditorBackground
        scrollView.contentView.drawsBackground = true
        scrollView.contentView.backgroundColor = .ezshotEditorBackground
        scrollView.documentView = canvas

        addSubview(scrollView)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        scrollView.contentView.scroll(to: .zero)
        scrollView.reflectScrolledClipView(scrollView.contentView)
        refreshEditorBackground()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(canvas)
        refreshEditorBackground()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshEditorBackground()
    }

    private func refreshEditorBackground() {
        let color = NSColor.ezshotEditorBackground(for: effectiveAppearance)
        scrollView.backgroundColor = color
        scrollView.contentView.backgroundColor = color
        canvas.refreshBackground()
    }

    func undo() {
        canvas.undo()
    }

    func copyImageToPasteboard() {
        canvas.copyImageToPasteboard()
    }
}

private enum CropHandle: CaseIterable {
    case topLeft
    case top
    case topRight
    case right
    case bottomRight
    case bottom
    case bottomLeft
    case left
}

private final class ScreenshotCanvasView: NSView {
    private enum DragOperation {
        case crop(CropHandle)
        case draw
    }

    private let padding: CGFloat = 16
    private let document: ScreenshotDocument
    var onDocumentChanged: (() -> Void)?
    var onModeChanged: ((ScreenshotEditMode) -> Void)?
    var mode: ScreenshotEditMode = .line {
        didSet {
            guard mode != oldValue else {
                return
            }
            onModeChanged?(mode)
            window?.invalidateCursorRects(for: self)
            needsDisplay = true
        }
    }
    var lineColor: NSColor = .systemRed {
        didSet { needsDisplay = true }
    }
    var lineWidth: CGFloat = 4 {
        didSet { needsDisplay = true }
    }
    var textValue: String = "Text" {
        didSet { needsDisplay = true }
    }
    var textFontName: String = NSFont.systemFont(ofSize: NSFont.systemFontSize).fontName {
        didSet { needsDisplay = true }
    }
    var textFontSize: CGFloat = 24 {
        didSet { needsDisplay = true }
    }
    var canUndo: Bool {
        !history.isEmpty
    }

    private var dragStart: CGPoint?
    private var dragCurrent: CGPoint?
    private var dragOperation: DragOperation?
    private var cropRect: CGRect
    private var cropRectAtDragStart: CGRect?
    private var cropDragViewStart: CGPoint?
    private var history: [NSImage] = []

    init(document: ScreenshotDocument) {
        self.document = document
        self.cropRect = CGRect(origin: .zero, size: document.image.size)
        super.init(frame: NSRect(origin: .zero, size: Self.paddedSize(for: document.image.size)))
        wantsLayer = true
        refreshBackground()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var isFlipped: Bool {
        true
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshBackground()
    }

    override func resetCursorRects() {
        super.resetCursorRects()

        for (handle, rect) in cropHandleRects() {
            addCursorRect(rect.insetBy(dx: -3, dy: -3), cursor: cursor(for: handle))
        }

        addCursorRect(viewRect(imageBounds), cursor: cursor(for: mode))
    }

    func refreshBackground() {
        layer?.backgroundColor = NSColor.ezshotEditorBackground(for: effectiveAppearance).cgColor
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.ezshotEditorBackground.setFill()
        dirtyRect.fill()
        drawImage()
        drawInProgressEdit()
        drawCropControls()
    }

    override func keyDown(with event: NSEvent) {
        guard
            event.modifierFlags.contains(.option),
            event.modifierFlags.intersection([.command, .control]).isEmpty
        else {
            super.keyDown(with: event)
            return
        }

        switch event.charactersIgnoringModifiers?.lowercased() {
        case "l":
            mode = .line
        case "a":
            mode = .arrow
        case "r":
            mode = .rectangle
        case "m":
            mode = .mosaic
        case "t":
            mode = .text
        default:
            super.keyDown(with: event)
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let rawViewPoint = convert(event.locationInWindow, from: nil)
        let point = boundedImagePoint(convertViewPointToImagePoint(rawViewPoint))
        dragStart = point
        dragCurrent = point

        if let cropHandle = cropHandle(atViewPoint: rawViewPoint) {
            dragOperation = .crop(cropHandle)
            cropRectAtDragStart = cropRect
            cropDragViewStart = rawViewPoint
        } else {
            dragOperation = .draw
        }

        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let rawViewPoint = convert(event.locationInWindow, from: nil)

        if
            case let .crop(handle) = dragOperation,
            let dragStart,
            let cropRectAtDragStart,
            let cropDragViewStart
        {
            let point = boundedImagePoint(CGPoint(
                x: dragStart.x + rawViewPoint.x - cropDragViewStart.x,
                y: dragStart.y + rawViewPoint.y - cropDragViewStart.y
            ))
            dragCurrent = point
            cropRect = adjustedCropRect(
                handle: handle,
                base: cropRectAtDragStart,
                from: dragStart,
                to: point
            )
            setFrameSize(Self.paddedSize(for: cropRect.size))
        } else {
            let point = boundedImagePoint(convertToImagePoint(event.locationInWindow))
            dragCurrent = point
        }

        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        let point = boundedImagePoint(convertToImagePoint(event.locationInWindow))
        dragCurrent = point

        switch dragOperation {
        case .crop:
            commitCrop()
        case .draw:
            switch mode {
            case .line:
                commitLine(arrow: false)
            case .arrow:
                commitLine(arrow: true)
            case .rectangle:
                commitRectangle()
            case .mosaic:
                commitMosaic()
            case .text:
                commitText()
            }
        case nil:
            break
        }

        dragStart = nil
        dragCurrent = nil
        dragOperation = nil
        cropRectAtDragStart = nil
        cropDragViewStart = nil
        needsDisplay = true
    }

    private var imageBounds: CGRect {
        CGRect(origin: .zero, size: document.image.size)
    }

    private var imageOrigin: CGPoint {
        CGPoint(x: padding, y: padding)
    }

    private var displayedImageRect: CGRect {
        if case .crop = dragOperation {
            return cropRect.integral.intersection(imageBounds)
        }

        return imageBounds
    }

    private static func paddedSize(for imageSize: CGSize) -> CGSize {
        CGSize(width: imageSize.width + 32, height: imageSize.height + 32)
    }

    private func drawImage() {
        guard
            let context = NSGraphicsContext.current?.cgContext,
            let cgImage = document.image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else {
            return
        }

        let visibleRect = displayedImageRect
        let destinationRect = CGRect(origin: imageOrigin, size: visibleRect.size)

        context.saveGState()
        context.clip(to: destinationRect)
        context.translateBy(
            x: imageOrigin.x - visibleRect.minX,
            y: imageOrigin.y + document.image.size.height - visibleRect.minY
        )
        context.scaleBy(x: 1, y: -1)
        context.draw(cgImage, in: imageBounds)
        context.restoreGState()
    }

    private func drawInProgressEdit() {
        guard
            let dragStart,
            let dragCurrent,
            case .draw = dragOperation
        else {
            return
        }

        switch mode {
        case .line:
            drawLine(from: dragStart, to: dragCurrent, arrow: false)
        case .arrow:
            drawLine(from: dragStart, to: dragCurrent, arrow: true)
        case .rectangle:
            drawRectangle(dragRect(from: dragStart, to: dragCurrent))
        case .mosaic:
            NSColor.systemBlue.withAlphaComponent(0.18).setFill()
            viewRect(dragRect(from: dragStart, to: dragCurrent)).fill()
            NSColor.systemBlue.setStroke()
            NSBezierPath(rect: viewRect(dragRect(from: dragStart, to: dragCurrent))).stroke()
        case .text:
            drawText(at: dragStart)
        }
    }

    private func drawCropControls() {
        NSColor.tertiaryLabelColor.setStroke()
        let path = NSBezierPath(rect: cropControlViewRect)
        path.lineWidth = 1
        path.stroke()

        NSColor.white.setFill()
        NSColor.secondaryLabelColor.setStroke()
        for rect in displayedCropHandleRects().values {
            let handle = NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2)
            handle.fill()
            handle.stroke()
        }
    }

    private func drawLine(from start: CGPoint, to end: CGPoint, arrow: Bool) {
        let path = linePath(from: viewPoint(start), to: viewPoint(end), arrow: arrow)
        lineColor.setStroke()
        path.stroke()
    }

    private func drawRectangle(_ rect: CGRect) {
        let path = NSBezierPath(rect: viewRect(rect))
        path.lineWidth = lineWidth
        lineColor.setStroke()
        path.stroke()
    }

    private func drawText(at point: CGPoint) {
        let attributed = attributedText()
        attributed.draw(at: viewPoint(point))
    }

    private func linePath(from start: CGPoint, to end: CGPoint, arrow: Bool) -> NSBezierPath {
        let path = NSBezierPath()
        path.lineWidth = lineWidth
        path.lineCapStyle = .round
        path.move(to: start)
        path.line(to: end)

        guard arrow else {
            return path
        }

        let angle = atan2(end.y - start.y, end.x - start.x)
        let length: CGFloat = 18
        let spread: CGFloat = .pi / 7
        let p1 = CGPoint(x: end.x - cos(angle - spread) * length, y: end.y - sin(angle - spread) * length)
        let p2 = CGPoint(x: end.x - cos(angle + spread) * length, y: end.y - sin(angle + spread) * length)
        path.move(to: p1)
        path.line(to: end)
        path.line(to: p2)
        return path
    }

    private func commitCrop() {
        let rect = cropRect.integral.intersection(imageBounds)
        guard rect.width >= 4, rect.height >= 4, rect != imageBounds else {
            cropRect = imageBounds
            setFrameSize(Self.paddedSize(for: document.image.size))
            return
        }

        pushUndo()
        updateDocument(rendered(size: rect.size) { context in
            drawDocumentImage(in: context, origin: CGPoint(x: -rect.minX, y: -rect.minY))
        })
    }

    private func commitLine(arrow: Bool) {
        guard
            let dragStart,
            let dragCurrent,
            hypot(dragCurrent.x - dragStart.x, dragCurrent.y - dragStart.y) > 3
        else {
            return
        }

        pushUndo()
        updateDocument(rendered(size: document.image.size) { context in
            drawDocumentImage(in: context, origin: .zero)
            context.setStrokeColor(lineColor.cgColor)
            context.setLineWidth(lineWidth)
            context.setLineCap(.round)
            context.addPath(linePath(from: dragStart, to: dragCurrent, arrow: arrow).cgPath)
            context.strokePath()
        })
    }

    private func commitRectangle() {
        guard
            let dragStart,
            let dragCurrent
        else {
            return
        }

        let rect = dragRect(from: dragStart, to: dragCurrent).integral.intersection(imageBounds)
        guard rect.width >= 4, rect.height >= 4 else {
            return
        }

        pushUndo()
        updateDocument(rendered(size: document.image.size) { context in
            drawDocumentImage(in: context, origin: .zero)
            context.setStrokeColor(lineColor.cgColor)
            context.setLineWidth(lineWidth)
            context.addRect(rect)
            context.strokePath()
        })
    }

    private func commitText() {
        guard
            let dragStart,
            !textValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return
        }

        pushUndo()
        updateDocument(rendered(size: document.image.size) { context in
            drawDocumentImage(in: context, origin: .zero)
            drawText(at: dragStart, in: context)
        })
    }

    private func commitMosaic() {
        guard
            let dragStart,
            let dragCurrent
        else {
            return
        }

        let rect = dragRect(from: dragStart, to: dragCurrent).integral.intersection(imageBounds)
        guard rect.width >= 6, rect.height >= 6 else {
            return
        }

        pushUndo()
        updateDocument(rendered(size: document.image.size) { context in
            drawDocumentImage(in: context, origin: .zero)
            drawMosaic(rect: rect, in: context)
        })
    }

    private func drawMosaic(rect: CGRect) {
        guard let context = NSGraphicsContext.current?.cgContext else {
            return
        }

        drawMosaic(rect: rect, in: context)
    }

    private func drawMosaic(rect: CGRect, in context: CGContext) {
        let blockSize: CGFloat = 6
        let crop = rendered(size: rect.size) { cropContext in
            drawDocumentImage(in: cropContext, origin: CGPoint(x: -rect.minX, y: -rect.minY))
        }
        let lowSize = CGSize(
            width: max((rect.width / blockSize).rounded(.up), 1),
            height: max((rect.height / blockSize).rounded(.up), 1)
        )
        let lowImage = renderImage(size: lowSize, flipped: false) { lowContext in
            lowContext.interpolationQuality = .medium
            drawImage(crop, in: CGRect(origin: .zero, size: lowSize), context: lowContext)
        }
        let pixelated = renderImage(size: rect.size, flipped: false) { pixelContext in
            pixelContext.interpolationQuality = .none
            drawImage(lowImage, in: CGRect(origin: .zero, size: rect.size), context: pixelContext)
        }

        drawImage(pixelated, in: rect, context: context)
    }

    private func rendered(size: CGSize, draw: (CGContext) -> Void) -> NSImage {
        renderImage(size: size, flipped: true, draw: draw)
    }

    private func renderImage(size: CGSize, flipped: Bool, draw: (CGContext) -> Void) -> NSImage {
        let width = max(Int(size.width.rounded(.up)), 1)
        let height = max(Int(size.height.rounded(.up)), 1)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard
            let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else {
            return document.image
        }

        context.interpolationQuality = .high
        if flipped {
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: 1, y: -1)
        }
        draw(context)

        guard let cgImage = context.makeImage() else {
            return document.image
        }

        return NSImage(cgImage: cgImage, size: size)
    }

    private func drawImage(_ image: NSImage, in rect: CGRect, context: CGContext) {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return
        }

        context.saveGState()
        context.translateBy(x: 0, y: rect.height + (rect.minY * 2))
        context.scaleBy(x: 1, y: -1)
        context.draw(cgImage, in: rect)
        context.restoreGState()
    }

    private func drawDocumentImage(in context: CGContext, origin: CGPoint) {
        guard let cgImage = document.image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return
        }

        let rect = CGRect(origin: origin, size: document.image.size)
        context.saveGState()
        context.translateBy(x: 0, y: rect.height + (origin.y * 2))
        context.scaleBy(x: 1, y: -1)
        context.draw(cgImage, in: rect)
        context.restoreGState()
    }

    private func drawText(at point: CGPoint, in context: CGContext) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        attributedText().draw(at: point)
        NSGraphicsContext.restoreGraphicsState()
    }

    private func attributedText() -> NSAttributedString {
        let font = NSFont(name: textFontName, size: textFontSize) ?? .systemFont(ofSize: textFontSize)
        return NSAttributedString(
            string: textValue,
            attributes: [
                .font: font,
                .foregroundColor: lineColor
            ]
        )
    }

    private func updateDocument(_ image: NSImage) {
        document.updateImage(image)
        setFrameSize(Self.paddedSize(for: image.size))
        cropRect = CGRect(origin: .zero, size: image.size)
        onDocumentChanged?()
        needsDisplay = true
    }

    func undo() {
        guard let previous = history.popLast() else {
            return
        }

        document.updateImage(previous)
        setFrameSize(Self.paddedSize(for: previous.size))
        cropRect = CGRect(origin: .zero, size: previous.size)
        onDocumentChanged?()
        needsDisplay = true
    }

    func copyImageToPasteboard() {
        document.copyToPasteboard()
    }

    private func pushUndo() {
        history.append(document.image.copy() as? NSImage ?? document.image)
    }

    private func bitmapImageRep() -> NSBitmapImageRep? {
        guard let tiff = document.image.tiffRepresentation else {
            return nil
        }
        return NSBitmapImageRep(data: tiff)
    }

    private func cropHandle(atViewPoint point: CGPoint) -> CropHandle? {
        cropHandleRects().first { $0.value.insetBy(dx: -3, dy: -3).contains(point) }?.key
    }

    private func cropHandleRects() -> [CropHandle: CGRect] {
        handleRects(for: cropRect)
    }

    private func displayedCropHandleRects() -> [CropHandle: CGRect] {
        if case .crop = dragOperation {
            return handleRects(for: CGRect(origin: .zero, size: displayedImageRect.size))
        }

        return cropHandleRects()
    }

    private var cropControlViewRect: CGRect {
        if case .crop = dragOperation {
            return viewRect(CGRect(origin: .zero, size: displayedImageRect.size))
        }

        return viewRect(cropRect)
    }

    private func handleRects(for imageRect: CGRect) -> [CropHandle: CGRect] {
        let size: CGFloat = 10
        let half = size / 2
        let points: [CropHandle: CGPoint] = [
            .topLeft: viewPoint(CGPoint(x: imageRect.minX, y: imageRect.minY)),
            .top: viewPoint(CGPoint(x: imageRect.midX, y: imageRect.minY)),
            .topRight: viewPoint(CGPoint(x: imageRect.maxX, y: imageRect.minY)),
            .right: viewPoint(CGPoint(x: imageRect.maxX, y: imageRect.midY)),
            .bottomRight: viewPoint(CGPoint(x: imageRect.maxX, y: imageRect.maxY)),
            .bottom: viewPoint(CGPoint(x: imageRect.midX, y: imageRect.maxY)),
            .bottomLeft: viewPoint(CGPoint(x: imageRect.minX, y: imageRect.maxY)),
            .left: viewPoint(CGPoint(x: imageRect.minX, y: imageRect.midY))
        ]
        return points.mapValues { point in
            CGRect(x: point.x - half, y: point.y - half, width: size, height: size)
        }
    }

    private func adjustedCropRect(handle: CropHandle, base: CGRect, from start: CGPoint, to current: CGPoint) -> CGRect {
        let dx = current.x - start.x
        let dy = current.y - start.y
        var rect = base

        switch handle {
        case .topLeft:
            rect.origin.x += dx
            rect.size.width -= dx
            rect.origin.y += dy
            rect.size.height -= dy
        case .top:
            rect.origin.y += dy
            rect.size.height -= dy
        case .topRight:
            rect.size.width += dx
            rect.origin.y += dy
            rect.size.height -= dy
        case .right:
            rect.size.width += dx
        case .bottomRight:
            rect.size.width += dx
            rect.size.height += dy
        case .bottom:
            rect.size.height += dy
        case .bottomLeft:
            rect.origin.x += dx
            rect.size.width -= dx
            rect.size.height += dy
        case .left:
            rect.origin.x += dx
            rect.size.width -= dx
        }

        rect = rect.standardized.intersection(imageBounds)
        if rect.width < 4 || rect.height < 4 {
            return base
        }
        return rect
    }

    private func dragRect(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(start.x - end.x),
            height: abs(start.y - end.y)
        )
    }

    private func bounded(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(point.x, imageBounds.minX), imageBounds.maxX),
            y: min(max(point.y, imageBounds.minY), imageBounds.maxY)
        )
    }

    private func boundedImagePoint(_ point: CGPoint) -> CGPoint {
        bounded(point)
    }

    private func convertToImagePoint(_ windowPoint: CGPoint) -> CGPoint {
        convertViewPointToImagePoint(convert(windowPoint, from: nil))
    }

    private func convertViewPointToImagePoint(_ viewPoint: CGPoint) -> CGPoint {
        return CGPoint(x: viewPoint.x - imageOrigin.x, y: viewPoint.y - imageOrigin.y)
    }

    private func viewPoint(_ imagePoint: CGPoint) -> CGPoint {
        CGPoint(x: imagePoint.x + imageOrigin.x, y: imagePoint.y + imageOrigin.y)
    }

    private func viewRect(_ imageRect: CGRect) -> CGRect {
        imageRect.offsetBy(dx: imageOrigin.x, dy: imageOrigin.y)
    }

    private func cursor(for handle: CropHandle) -> NSCursor {
        switch handle {
        case .topLeft, .bottomRight:
            .crosshair
        case .topRight, .bottomLeft:
            .crosshair
        case .top, .bottom:
            .resizeUpDown
        case .left, .right:
            .resizeLeftRight
        }
    }

    private func cursor(for mode: ScreenshotEditMode) -> NSCursor {
        switch mode {
        case .line:
            .crosshair
        case .arrow:
            .pointingHand
        case .rectangle:
            .crosshair
        case .mosaic:
            .operationNotAllowed
        case .text:
            .iBeam
        }
    }
}

private extension NSColor {
    static let ezshotEditorBackground = NSColor(name: nil) { appearance in
        ezshotEditorBackground(for: appearance)
    }

    static func ezshotEditorBackground(for appearance: NSAppearance) -> NSColor {
        if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return NSColor(calibratedWhite: 0.18, alpha: 1)
        }

        return NSColor(calibratedWhite: 0.88, alpha: 1)
    }
}
