import AppKit
import EzshotCore

@MainActor
final class CaptureDelayMenuController: NSObject {
    private let preferences: PreferencesStore
    private let onChange: () -> Void
    private var delayItems: [NSMenuItem] = []
    private var customDelayItem: NSMenuItem?

    init(preferences: PreferencesStore, onChange: @escaping () -> Void = {}) {
        self.preferences = preferences
        self.onChange = onChange
        super.init()
    }

    func makeMenu() -> NSMenu {
        delayItems.removeAll()
        customDelayItem = nil

        let menu = NSMenu(title: "Capture Delay")
        for seconds in [0, 1, 3, 5, 10] {
            let item = NSMenuItem(
                title: delayTitle(for: Double(seconds)),
                action: #selector(selectCaptureDelay(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = seconds
            menu.addItem(item)
            delayItems.append(item)
        }

        menu.addItem(.separator())
        let customDelayItem = NSMenuItem(
            title: "Custom...",
            action: #selector(showCustomDelayPanel),
            keyEquivalent: ""
        )
        customDelayItem.target = self
        menu.addItem(customDelayItem)
        self.customDelayItem = customDelayItem
        updateMenuItems()
        return menu
    }

    func updateMenuItems() {
        let currentDelay = preferences.captureDelaySeconds
        for item in delayItems {
            item.state = abs(Double(item.tag) - currentDelay) < 0.001 ? .on : .off
        }

        let isCustomDelay = ![0, 1, 3, 5, 10].contains { abs(Double($0) - currentDelay) < 0.001 }
        customDelayItem?.state = isCustomDelay ? .on : .off
        customDelayItem?.title = isCustomDelay ? "Custom... (\(Self.formatDelay(currentDelay)))" : "Custom..."
    }

    static func label(for seconds: Double) -> String {
        seconds == 0 ? "Delay: Off" : "Delay: \(formatDelay(seconds))"
    }

    static func localizedLabel(for seconds: Double, preferences: PreferencesStore) -> String {
        let localizer = AppLocalizer(preferences: preferences)
        return seconds == 0
            ? "\(localizer.text(.delay)): \(localizer.text(.off))"
            : "\(localizer.text(.delay)): \(formatDelay(seconds))"
    }

    private func delayTitle(for seconds: Double) -> String {
        seconds == 0 ? "Off" : Self.formatDelay(seconds)
    }

    private static func formatDelay(_ seconds: Double) -> String {
        if seconds.rounded() == seconds {
            return "\(Int(seconds))s"
        }

        return "\(String(format: "%.1f", seconds))s"
    }

    @objc private func selectCaptureDelay(_ sender: NSMenuItem) {
        preferences.captureDelaySeconds = Double(sender.tag)
        updateMenuItems()
        onChange()
    }

    @objc private func showCustomDelayPanel() {
        let alert = NSAlert()
        alert.messageText = "Custom Capture Delay"
        alert.informativeText = "Enter delay in seconds."
        alert.addButton(withTitle: "Set")
        alert.addButton(withTitle: "Cancel")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 160, height: 24))
        input.stringValue = Self.inputValue(for: preferences.captureDelaySeconds)
        input.placeholderString = "Seconds"
        alert.accessoryView = input

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        let value = input.doubleValue
        guard value >= 0 else {
            NSSound.beep()
            return
        }

        preferences.captureDelaySeconds = value
        updateMenuItems()
        onChange()
    }

    private static func inputValue(for seconds: Double) -> String {
        seconds.rounded() == seconds ? "\(Int(seconds))" : String(format: "%.1f", seconds)
    }
}
