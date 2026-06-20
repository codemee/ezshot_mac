import AppKit
import EzshotCore
import Foundation

@main
struct EzshotCoreTests {
    static func main() throws {
        try testAutoCopyDefaultsToEnabled()
        try testAutoCopyPersistsChanges()
        try testCaptureDelayDefaultsToOff()
        try testCaptureDelayPersistsCustomValue()
        try testCaptureDelayClampsNegativeValue()
        try testLanguageModeDefaultsToSystemAndPersists()
        try testAppearanceModeDefaultsToSystemAndPersists()
        try testDefaultFileNameUsesPNGTimestampFormat()
        try testCustomTabTitleOverridesScreenshotTitle()
        try testSaveWritesPNGAndClearsDirtyState()
        try testSaveWritesJPEGAndClearsDirtyState()
        try testUpdateImageMarksDocumentDirty()
        try testOverwriteRequiresExistingFileURL()
        try testOverwriteWritesToExistingURL()
        print("All EzshotCore tests passed.")
    }

    private static func testAutoCopyDefaultsToEnabled() throws {
        let defaults = makeDefaults()
        let store = PreferencesStore(defaults: defaults)

        try expect(store.autoCopyAfterCapture, "auto copy should default to enabled")
    }

    private static func testAutoCopyPersistsChanges() throws {
        let defaults = makeDefaults()
        let store = PreferencesStore(defaults: defaults)

        store.autoCopyAfterCapture = false

        try expect(
            PreferencesStore(defaults: defaults).autoCopyAfterCapture == false,
            "auto copy should persist disabled value"
        )
    }

    private static func testCaptureDelayDefaultsToOff() throws {
        let defaults = makeDefaults()
        let store = PreferencesStore(defaults: defaults)

        try expect(store.captureDelaySeconds == 0, "capture delay should default to off")
    }

    private static func testCaptureDelayPersistsCustomValue() throws {
        let defaults = makeDefaults()
        let store = PreferencesStore(defaults: defaults)

        store.captureDelaySeconds = 2.5

        try expect(
            PreferencesStore(defaults: defaults).captureDelaySeconds == 2.5,
            "capture delay should persist custom seconds"
        )
    }

    private static func testCaptureDelayClampsNegativeValue() throws {
        let defaults = makeDefaults()
        let store = PreferencesStore(defaults: defaults)

        store.captureDelaySeconds = -3

        try expect(store.captureDelaySeconds == 0, "capture delay should clamp negative values to zero")
    }

    private static func testLanguageModeDefaultsToSystemAndPersists() throws {
        let defaults = makeDefaults()
        let store = PreferencesStore(defaults: defaults)

        try expect(store.languageMode == "system", "language mode should default to system")

        store.languageMode = "zh-Hant"

        try expect(
            PreferencesStore(defaults: defaults).languageMode == "zh-Hant",
            "language mode should persist"
        )
    }

    private static func testAppearanceModeDefaultsToSystemAndPersists() throws {
        let defaults = makeDefaults()
        let store = PreferencesStore(defaults: defaults)

        try expect(store.appearanceMode == "system", "appearance mode should default to system")

        store.appearanceMode = "dark"

        try expect(
            PreferencesStore(defaults: defaults).appearanceMode == "dark",
            "appearance mode should persist"
        )
    }

    private static func testDefaultFileNameUsesPNGTimestampFormat() throws {
        let date = Date(timeIntervalSince1970: 1_704_067_205)
        let document = ScreenshotDocument(image: makeImage(), createdAt: date)

        try expect(
            document.defaultFileName == "Screenshot 2024-01-01 08.00.05.png",
            "default file name should use expected local timestamp"
        )
        try expect(document.defaultFileName.hasSuffix(".png"), "default file name should be a PNG")
    }

    private static func testSaveWritesPNGAndClearsDirtyState() throws {
        let document = ScreenshotDocument(image: makeImage())
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("png")
        defer {
            try? FileManager.default.removeItem(at: url)
        }

        try document.save(to: url)

        try expect(document.fileURL == url, "save should remember file URL")
        try expect(document.tabTitle == url.deletingPathExtension().lastPathComponent, "save should update tab title from file name")
        try expect(document.isDirty == false, "save should clear dirty state")
        try expect(FileManager.default.fileExists(atPath: url.path), "save should write PNG file")
    }

    private static func testSaveWritesJPEGAndClearsDirtyState() throws {
        let document = ScreenshotDocument(image: makeImage())
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("jpg")
        defer {
            try? FileManager.default.removeItem(at: url)
        }

        try document.save(to: url)

        let data = try Data(contentsOf: url)
        try expect(document.fileURL == url, "JPEG save should remember file URL")
        try expect(document.isDirty == false, "JPEG save should clear dirty state")
        try expect(data.starts(with: [0xFF, 0xD8]), "save should write JPEG data")
    }

    private static func testCustomTabTitleOverridesScreenshotTitle() throws {
        let document = ScreenshotDocument(image: makeImage(), tabTitle: "Original File")

        try expect(document.tabTitle == "Original File", "custom tab title should be retained")
    }

    private static func testOverwriteRequiresExistingFileURL() throws {
        let document = ScreenshotDocument(image: makeImage())

        do {
            try document.overwrite()
            throw TestFailure("overwrite without URL should throw")
        } catch ScreenshotDocumentError.missingFileURL {
            return
        }
    }

    private static func testUpdateImageMarksDocumentDirty() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("png")
        defer {
            try? FileManager.default.removeItem(at: url)
        }

        let document = ScreenshotDocument(image: makeImage())
        try document.save(to: url)
        document.updateImage(NSImage(size: NSSize(width: 4, height: 4)))

        try expect(document.image.size == NSSize(width: 4, height: 4), "update should replace image")
        try expect(document.isDirty, "update should mark document dirty")
    }

    private static func testOverwriteWritesToExistingURL() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("png")
        defer {
            try? FileManager.default.removeItem(at: url)
        }

        let document = ScreenshotDocument(image: makeImage())
        try document.save(to: url)
        try document.overwrite()

        try expect(document.fileURL == url, "overwrite should retain existing file URL")
        try expect(document.isDirty == false, "overwrite should keep dirty state clear")
    }

    private static func makeDefaults() -> UserDefaults {
        let suiteName = "EzshotCoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private static func makeImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 8, height: 8))
        image.lockFocus()
        NSColor.systemTeal.setFill()
        NSRect(x: 0, y: 0, width: 8, height: 8).fill()
        image.unlockFocus()
        return image
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else {
            throw TestFailure(message)
        }
    }
}

private struct TestFailure: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}
