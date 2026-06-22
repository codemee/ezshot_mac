import AppKit
import Carbon.HIToolbox
import CoreGraphics
import EzshotCore
import ScreenCaptureKit

@MainActor
final class CaptureController {
    private let preferences: PreferencesStore
    private let onCapture: (ScreenshotDocument) -> Void
    private var hotKeys: [GlobalHotKey] = []
    private var overlays: [SelectionOverlayWindow] = []
    private var windowSelectionOverlays: [WindowSelectionOverlayWindow] = []
    private var retiredOverlays: [[SelectionOverlayWindow]] = []
    private var retiredWindowSelectionOverlays: [[WindowSelectionOverlayWindow]] = []
    private var countdownOverlay: CountdownOverlayController?
    private var hasRequestedScreenRecordingAccess = false

    init(
        preferences: PreferencesStore,
        onCapture: @escaping (ScreenshotDocument) -> Void
    ) {
        self.preferences = preferences
        self.onCapture = onCapture
    }

    func start() {
        hotKeys = [
            GlobalHotKey(id: 1, keyCode: UInt32(kVK_ANSI_R), modifiers: [.option, .shift]) { [weak self] in
                self?.captureSelection()
            },
            GlobalHotKey(id: 2, keyCode: UInt32(kVK_ANSI_A), modifiers: [.option, .shift]) { [weak self] in
                self?.captureActiveWindow()
            },
            GlobalHotKey(id: 3, keyCode: UInt32(kVK_ANSI_W), modifiers: [.option, .shift]) { [weak self] in
                self?.capturePickedWindow()
            },
            GlobalHotKey(id: 4, keyCode: UInt32(kVK_ANSI_F), modifiers: [.option, .shift]) { [weak self] in
                self?.captureFullscreen()
            }
        ]
        hotKeys.forEach { $0.register() }
    }

    func captureSelection() {
        guard ensureScreenRecordingAccess() else {
            return
        }

        showSelectionOverlays()
    }

    func captureFullscreen() {
        guard ensureScreenRecordingAccess() else {
            return
        }

        captureAfterDelay { [weak self] in
            self?.captureMainDisplay()
        }
    }

    func captureActiveWindow() {
        guard ensureScreenRecordingAccess() else {
            return
        }

        guard let window = capturableWindows().first else {
            showCaptureFailedAlert(CaptureError.noWindowAvailable)
            return
        }

        captureAfterDelay { [weak self] in
            self?.capture(window: window)
        }
    }

    func capturePickedWindow() {
        guard ensureScreenRecordingAccess() else {
            return
        }

        showWindowSelectionOverlays()
    }

    private func showSelectionOverlays() {
        closeSelectionOverlays()
        closeWindowSelectionOverlays()

        overlays = NSScreen.screens.map { screen in
            SelectionOverlayWindow(screen: screen) { [weak self] rect in
                DispatchQueue.main.async {
                    self?.finishSelection(rect: rect)
                }
            } onCancel: { [weak self] in
                DispatchQueue.main.async {
                    self?.retireSelectionOverlays()
                }
            }
        }

        overlays.forEach { window in
            window.orderFrontRegardless()
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(window.contentView)
            window.beginSelectionCursor()
        }
    }

    private func showWindowSelectionOverlays() {
        closeSelectionOverlays()
        closeWindowSelectionOverlays()

        let windows = capturableWindows(includingCurrentProcess: true)
        windowSelectionOverlays = NSScreen.screens.map { screen in
            WindowSelectionOverlayWindow(screen: screen, windows: windows) { [weak self] window in
                DispatchQueue.main.async {
                    self?.finishWindowSelection(window: window)
                }
            } onCancel: { [weak self] in
                DispatchQueue.main.async {
                    self?.retireWindowSelectionOverlays()
                }
            }
        }

        windowSelectionOverlays.forEach { window in
            window.orderFrontRegardless()
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(window.contentView)
        }
    }

    private func finishSelection(rect: CGRect) {
        retireSelectionOverlays()

        captureAfterDelay { [weak self] in
            self?.capture(rect: rect)
        }
    }

    private func finishWindowSelection(window: CapturableWindow) {
        retireWindowSelectionOverlays()

        captureAfterDelay { [weak self] in
            self?.capture(window: window)
        }
    }

    private func captureAfterDelay(_ action: @escaping @MainActor () -> Void) {
        let delay = preferences.captureDelaySeconds
        guard delay > 0 else {
            // Give WindowServer a moment to remove selection overlays before
            // ScreenCaptureKit snapshots the display.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                action()
            }
            return
        }

        countdownOverlay?.cancel()
        countdownOverlay = CountdownOverlayController(seconds: delay) { [weak self] in
            self?.countdownOverlay = nil
            action()
        }
        countdownOverlay?.start()
    }

    private func closeSelectionOverlays() {
        overlays.forEach { window in
            window.endSelectionCursor()
            window.close()
        }
        overlays.removeAll()
    }

    private func closeWindowSelectionOverlays() {
        windowSelectionOverlays.forEach { window in
            window.endSelectionCursor()
            window.close()
        }
        windowSelectionOverlays.removeAll()
    }

    private func retireSelectionOverlays() {
        let windows = overlays
        overlays.removeAll()

        windows.forEach { window in
            window.endSelectionCursor()
            window.alphaValue = 0
            window.ignoresMouseEvents = true
            window.orderOut(nil)
        }
        retiredOverlays.append(windows)

        // Keep hidden overlay windows alive for the app lifetime. Closing them
        // immediately after mouse-up can crash inside AppKit/CGS while the
        // selection event is still being unwound.
    }

    private func retireWindowSelectionOverlays() {
        let windows = windowSelectionOverlays
        windowSelectionOverlays.removeAll()

        windows.forEach { window in
            window.endSelectionCursor()
            window.alphaValue = 0
            window.ignoresMouseEvents = true
            window.orderOut(nil)
        }
        retiredWindowSelectionOverlays.append(windows)
    }

    private func ensureScreenRecordingAccess() -> Bool {
        if CGPreflightScreenCaptureAccess() {
            return true
        }

        if !hasRequestedScreenRecordingAccess {
            hasRequestedScreenRecordingAccess = true
            let granted = CGRequestScreenCaptureAccess()
            if granted {
                return true
            }
            showScreenRecordingPermissionAlert()
            return false
        }

        showScreenRecordingPermissionAlert()
        return false
    }

    private func capture(rect: CGRect) {
        Task {
            do {
                let image = try await captureImage(in: rect)
                let document = ScreenshotDocument(image: image)
                if preferences.autoCopyAfterCapture {
                    document.copyToPasteboard()
                }
                await MainActor.run {
                    self.onCapture(document)
                }
            } catch {
                await MainActor.run {
                    self.showCaptureFailedAlert(error)
                }
            }
        }
    }

    private func capture(window: CapturableWindow) {
        do {
            let image = try captureWindowImage(window)
            let document = ScreenshotDocument(image: image)
            if preferences.autoCopyAfterCapture {
                document.copyToPasteboard()
            }
            onCapture(document)
        } catch {
            showCaptureFailedAlert(error)
        }
    }

    private func captureMainDisplay() {
        Task {
            do {
                let image = try await captureMainDisplayImage()
                let document = ScreenshotDocument(image: image)
                if preferences.autoCopyAfterCapture {
                    document.copyToPasteboard()
                }
                await MainActor.run {
                    self.onCapture(document)
                }
            } catch {
                await MainActor.run {
                    self.showCaptureFailedAlert(error)
                }
            }
        }
    }

    private func captureWindowImage(_ window: CapturableWindow) throws -> NSImage {
        guard let cgImage = CGWindowListCreateImage(
            .null,
            [.optionIncludingWindow],
            window.id,
            [.boundsIgnoreFraming, .bestResolution]
        ) else {
            throw CaptureError.windowCaptureFailed
        }

        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    private func capturableWindows(includingCurrentProcess: Bool = false) -> [CapturableWindow] {
        guard let infos = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        let currentPID = NSRunningApplication.current.processIdentifier
        return infos.compactMap { info in
            guard
                let id = info[kCGWindowNumber as String] as? CGWindowID,
                let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t,
                includingCurrentProcess || ownerPID != currentPID,
                let layer = info[kCGWindowLayer as String] as? Int,
                layer == 0,
                let alpha = info[kCGWindowAlpha as String] as? Double,
                alpha > 0,
                let boundsDict = info[kCGWindowBounds as String] as? NSDictionary
            else {
                return nil
            }

            var bounds = CGRect.zero
            guard CGRectMakeWithDictionaryRepresentation(boundsDict, &bounds), bounds.width > 20, bounds.height > 20 else {
                return nil
            }

            let ownerName = info[kCGWindowOwnerName as String] as? String ?? "Window"
            return CapturableWindow(id: id, bounds: bounds, ownerName: ownerName)
        }
    }

    private func captureImage(in rect: CGRect) async throws -> NSImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = display(containing: rect, from: content.displays) ?? content.displays.first else {
            throw CaptureError.noDisplayAvailable
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.width = Int(display.width)
        configuration.height = Int(display.height)
        configuration.showsCursor = false
        configuration.scalesToFit = false

        let cgImage = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: configuration
        )

        let displayFrame = screenFrame(for: display) ?? NSScreen.main?.frame ?? rect
        let localRect = CGRect(
            x: rect.minX - displayFrame.minX,
            y: displayFrame.maxY - rect.maxY,
            width: rect.width,
            height: rect.height
        ).integral

        guard let cropped = cgImage.cropping(to: localRect) else {
            throw CaptureError.cropFailed
        }

        return NSImage(cgImage: cropped, size: NSSize(width: cropped.width, height: cropped.height))
    }

    private func captureMainDisplayImage() async throws -> NSImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let mainDisplayID = NSScreen.main?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
        guard
            let display = content.displays.first(where: { $0.displayID == mainDisplayID }) ?? content.displays.first
        else {
            throw CaptureError.noDisplayAvailable
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.width = Int(display.width)
        configuration.height = Int(display.height)
        configuration.showsCursor = false
        configuration.scalesToFit = false

        let cgImage = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: configuration
        )

        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    private func display(containing rect: CGRect, from displays: [SCDisplay]) -> SCDisplay? {
        displays.first { display in
            guard let frame = screenFrame(for: display) else {
                return false
            }
            return frame.intersects(rect)
        }
    }

    private func screenFrame(for display: SCDisplay) -> CGRect? {
        NSScreen.screens.first { screen in
            screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID == display.displayID
        }?.frame
    }

    private func showScreenRecordingPermissionAlert() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
    }

    private func showCaptureFailedAlert(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.messageText = "Capture Failed"
        alert.runModal()
    }
}

private enum CaptureError: LocalizedError {
    case noDisplayAvailable
    case cropFailed
    case noWindowAvailable
    case windowCaptureFailed

    var errorDescription: String? {
        switch self {
        case .noDisplayAvailable:
            "No display was available for capture."
        case .cropFailed:
            "The selected area could not be cropped from the captured display."
        case .noWindowAvailable:
            "No capturable window was available."
        case .windowCaptureFailed:
            "The selected window could not be captured."
        }
    }
}
