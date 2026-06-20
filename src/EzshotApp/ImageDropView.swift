import AppKit

final class ImageDropView: NSView {
    private let onDropURLs: ([URL]) -> Void
    private var isDragTargeted = false {
        didSet {
            needsDisplay = true
        }
    }

    init(onDropURLs: @escaping ([URL]) -> Void) {
        self.onDropURLs = onDropURLs
        super.init(frame: .zero)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard !imageURLs(from: sender.draggingPasteboard).isEmpty else {
            return []
        }

        isDragTargeted = true
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        imageURLs(from: sender.draggingPasteboard).isEmpty ? [] : .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        isDragTargeted = false
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let droppedURLs = imageURLs(from: sender.draggingPasteboard)
        isDragTargeted = false
        guard !droppedURLs.isEmpty else {
            return false
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [onDropURLs] in
            onDropURLs(droppedURLs)
        }
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard isDragTargeted else {
            return
        }

        NSColor.controlAccentColor.withAlphaComponent(0.14).setFill()
        bounds.fill()

        NSColor.controlAccentColor.setStroke()
        let border = NSBezierPath(roundedRect: bounds.insetBy(dx: 8, dy: 8), xRadius: 8, yRadius: 8)
        border.lineWidth = 3
        border.stroke()
    }

    private func imageURLs(from pasteboard: NSPasteboard) -> [URL] {
        guard
            let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [
                .urlReadingFileURLsOnly: true
            ]) as? [URL]
        else {
            return []
        }

        return urls.filter { url in
            Self.supportedImageExtensions.contains(url.pathExtension.lowercased())
        }
    }

    private static let supportedImageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "heic", "heif", "gif", "tif", "tiff", "bmp", "webp"
    ]
}
