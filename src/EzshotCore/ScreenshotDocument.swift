import AppKit
import Foundation

public enum ScreenshotDocumentError: Error, Equatable {
    case missingFileURL
    case pngEncodingFailed
    case jpegEncodingFailed
}

public final class ScreenshotDocument: Identifiable {
    public let id: UUID
    public private(set) var image: NSImage
    public let createdAt: Date
    public private(set) var tabTitle: String
    public private(set) var fileURL: URL?
    public private(set) var isDirty: Bool

    public init(
        id: UUID = UUID(),
        image: NSImage,
        createdAt: Date = Date(),
        tabTitle: String? = nil,
        fileURL: URL? = nil,
        isDirty: Bool = true
    ) {
        self.id = id
        self.image = image
        self.createdAt = createdAt
        self.tabTitle = tabTitle ?? "Screenshot \(Self.tabTimeFormatter.string(from: createdAt))"
        self.fileURL = fileURL
        self.isDirty = isDirty
    }

    public var defaultFileName: String {
        "Screenshot \(Self.fileNameDateFormatter.string(from: createdAt)).png"
    }

    public func save(to url: URL) throws {
        guard let data = image.imageData(for: url) else {
            if url.isJPEG {
                throw ScreenshotDocumentError.jpegEncodingFailed
            }

            throw ScreenshotDocumentError.pngEncodingFailed
        }

        try data.write(to: url, options: .atomic)
        fileURL = url
        tabTitle = url.deletingPathExtension().lastPathComponent
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
    func imageData(for url: URL) -> Data? {
        if url.isJPEG {
            return jpegData()
        }

        return pngData()
    }

    func pngData() -> Data? {
        guard
            let tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiffRepresentation)
        else {
            return nil
        }

        return bitmap.representation(using: .png, properties: [:])
    }

    func jpegData() -> Data? {
        guard
            let tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiffRepresentation)
        else {
            return nil
        }

        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.92])
    }
}

private extension URL {
    var isJPEG: Bool {
        let ext = pathExtension.lowercased()
        return ext == "jpg" || ext == "jpeg"
    }
}
