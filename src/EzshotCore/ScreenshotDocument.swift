import AppKit
import Foundation

public enum ScreenshotDocumentError: Error, Equatable {
    case missingFileURL
    case pngEncodingFailed
}

public final class ScreenshotDocument: Identifiable {
    public let id: UUID
    public private(set) var image: NSImage
    public let createdAt: Date
    public private(set) var fileURL: URL?
    public private(set) var isDirty: Bool

    public init(
        id: UUID = UUID(),
        image: NSImage,
        createdAt: Date = Date(),
        fileURL: URL? = nil,
        isDirty: Bool = true
    ) {
        self.id = id
        self.image = image
        self.createdAt = createdAt
        self.fileURL = fileURL
        self.isDirty = isDirty
    }

    public var tabTitle: String {
        "Screenshot \(Self.tabTimeFormatter.string(from: createdAt))"
    }

    public var defaultFileName: String {
        "Screenshot \(Self.fileNameDateFormatter.string(from: createdAt)).png"
    }

    public func save(to url: URL) throws {
        guard let data = image.pngData() else {
            throw ScreenshotDocumentError.pngEncodingFailed
        }

        try data.write(to: url, options: .atomic)
        fileURL = url
        isDirty = false
    }

    public func overwrite() throws {
        guard let fileURL else {
            throw ScreenshotDocumentError.missingFileURL
        }

        try save(to: fileURL)
    }

    public func copyToPasteboard(_ pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
    }

    public func updateImage(_ image: NSImage) {
        self.image = image
        isDirty = true
    }
}

public extension ScreenshotDocument {
    static let tabTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    static let fileNameDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return formatter
    }()
}

private extension NSImage {
    func pngData() -> Data? {
        guard
            let tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiffRepresentation)
        else {
            return nil
        }

        return bitmap.representation(using: .png, properties: [:])
    }
}
