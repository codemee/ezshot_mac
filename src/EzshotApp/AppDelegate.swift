import AppKit
import EzshotCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let preferences = PreferencesStore()
    private lazy var tabsController = ScreenshotTabsViewController(preferences: preferences)
    private lazy var captureController = CaptureController(preferences: preferences) { [weak self] document in
        self?.handleCapturedDocument(document)
    }

    private var statusItem: NSStatusItem?
    private var statusMenu: NSMenu?
    private var autoCopyItem: NSMenuItem?
    private var delaySettingsController: CaptureDelayPopoverViewController?
    private lazy var settingsMenuController = AppSettingsMenuController(preferences: preferences) { [weak self] in
        self?.refreshChrome()
    }
    private var statusClickWorkItem: DispatchWorkItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        AppSettingsMenuController.applyAppearance(preferences: preferences)
        configureStatusItem()
        captureController.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func configureStatusItem() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = makeStatusBarIcon()
        statusItem.button?.toolTip = "Ezshot"
        statusItem.button?.target = self
        statusItem.button?.action = #selector(handleStatusItemClick)
        statusItem.button?.sendAction(on: [.leftMouseDown])

        self.statusItem = statusItem
        rebuildStatusMenu()
    }

    private func rebuildStatusMenu() {
        let localizer = AppLocalizer(preferences: preferences)
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(NSMenuItem(
            title: localizer.text(.captureSelection),
            action: #selector(captureSelection),
            keyEquivalent: "r"
        ))
        menu.items.last?.keyEquivalentModifierMask = [.option, .shift]

        menu.addItem(NSMenuItem(
            title: localizer.text(.captureActiveWindow),
            action: #selector(captureActiveWindow),
            keyEquivalent: "a"
        ))
        menu.items.last?.keyEquivalentModifierMask = [.option, .shift]

        menu.addItem(NSMenuItem(
            title: localizer.text(.pickWindow),
            action: #selector(capturePickedWindow),
            keyEquivalent: "w"
        ))
        menu.items.last?.keyEquivalentModifierMask = [.option, .shift]

        menu.addItem(NSMenuItem(
            title: localizer.text(.showScreenshots),
            action: #selector(showScreenshots),
            keyEquivalent: "0"
        ))

        let autoCopyItem = NSMenuItem(
            title: localizer.text(.autoCopy),
            action: #selector(toggleAutoCopy),
            keyEquivalent: ""
        )
        menu.addItem(autoCopyItem)
        self.autoCopyItem = autoCopyItem
        updateAutoCopyMenuItem()

        menu.addItem(.separator())
        let delaySettingsController = CaptureDelayPopoverViewController(preferences: preferences)
        let delaySettingsItem = NSMenuItem()
        delaySettingsItem.view = delaySettingsController.view
        menu.addItem(delaySettingsItem)
        self.delaySettingsController = delaySettingsController

        menu.addItem(.separator())
        let languageItem = NSMenuItem(title: localizer.text(.language), action: nil, keyEquivalent: "")
        languageItem.submenu = settingsMenuController.makeLanguageMenu(localizer: localizer)
        menu.addItem(languageItem)

        let appearanceItem = NSMenuItem(title: localizer.text(.appearance), action: nil, keyEquivalent: "")
        appearanceItem.submenu = settingsMenuController.makeAppearanceMenu(localizer: localizer)
        menu.addItem(appearanceItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(
            title: localizer.text(.quit),
            action: #selector(quit),
            keyEquivalent: "q"
        ))

        statusMenu = menu
    }

    private func makeStatusBarIcon() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18))
        image.lockFocus()
        NSColor.labelColor.setStroke()
        NSColor.labelColor.setFill()

        let top = NSBezierPath(roundedRect: NSRect(x: 6.2, y: 12.2, width: 5.6, height: 2.3), xRadius: 0.9, yRadius: 0.9)
        top.fill()

        let body = NSBezierPath(roundedRect: NSRect(x: 2.6, y: 4.2, width: 12.8, height: 9.3), xRadius: 2.1, yRadius: 2.1)
        body.lineWidth = 1.9
        body.stroke()

        let shutter = NSBezierPath(roundedRect: NSRect(x: 12.2, y: 11.2, width: 1.8, height: 1.1), xRadius: 0.5, yRadius: 0.5)
        shutter.fill()

        let lens = NSBezierPath(ovalIn: NSRect(x: 5.7, y: 5.8, width: 6.6, height: 6.6))
        lens.lineWidth = 1.8
        lens.stroke()

        let innerLens = NSBezierPath(ovalIn: NSRect(x: 7.9, y: 8, width: 2.2, height: 2.2))
        innerLens.fill()

        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    private func handleCapturedDocument(_ document: ScreenshotDocument) {
        tabsController.addDocument(document)
        tabsController.showWindow()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func updateAutoCopyMenuItem() {
        autoCopyItem?.state = preferences.autoCopyAfterCapture ? .on : .off
    }

    private func refreshChrome() {
        rebuildStatusMenu()
        tabsController.refreshChrome()
    }

    @objc private func handleStatusItemClick() {
        guard let event = NSApp.currentEvent else {
            showStatusMenu()
            return
        }

        statusClickWorkItem?.cancel()
        if event.clickCount >= 2 {
            showScreenshots()
            return
        }

        let workItem = DispatchWorkItem { [weak self] in
            self?.showStatusMenu()
        }
        statusClickWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22, execute: workItem)
    }

    private func showStatusMenu() {
        guard
            let statusItem,
            let statusMenu
        else {
            return
        }

        statusItem.popUpMenu(statusMenu)
    }

    @objc private func captureSelection() {
        captureController.captureSelection()
    }

    @objc private func captureActiveWindow() {
        captureController.captureActiveWindow()
    }

    @objc private func capturePickedWindow() {
        captureController.capturePickedWindow()
    }

    @objc private func showScreenshots() {
        tabsController.showWindow()
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func toggleAutoCopy() {
        preferences.autoCopyAfterCapture.toggle()
        updateAutoCopyMenuItem()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        delaySettingsController?.refresh()
    }
}
