import AppKit
import EzshotCore
import ServiceManagement

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
    private var launchAtLoginItem: NSMenuItem?
    private var delaySettingsController: CaptureDelayPopoverViewController?
    private lazy var settingsMenuController = AppSettingsMenuController(preferences: preferences) { [weak self] in
        self?.refreshChrome()
    }
    private var statusClickWorkItem: DispatchWorkItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.applicationIconImage = AppIconFactory.makeApplicationIcon()
        AppSettingsMenuController.applyAppearance(preferences: preferences)
        configureStatusItem()
        captureController.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func configureStatusItem() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = AppIconFactory.makeStatusIcon()
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

        let launchAtLoginItem = NSMenuItem(
            title: localizer.text(.launchAtLogin),
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        menu.addItem(launchAtLoginItem)
        self.launchAtLoginItem = launchAtLoginItem
        syncLaunchAtLoginPreference()
        updateLaunchAtLoginMenuItem()

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

    private func handleCapturedDocument(_ document: ScreenshotDocument) {
        tabsController.addDocument(document)
        tabsController.showWindow()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func updateAutoCopyMenuItem() {
        autoCopyItem?.state = preferences.autoCopyAfterCapture ? .on : .off
    }

    private func updateLaunchAtLoginMenuItem() {
        launchAtLoginItem?.state = preferences.launchAtLogin ? .on : .off
    }

    private func syncLaunchAtLoginPreference() {
        switch SMAppService.mainApp.status {
        case .enabled:
            preferences.launchAtLogin = true
        case .notRegistered:
            preferences.launchAtLogin = false
        default:
            break
        }
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

    @objc private func toggleLaunchAtLogin() {
        let newValue = !preferences.launchAtLogin

        do {
            if newValue {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            preferences.launchAtLogin = newValue
        } catch {
            let localizer = AppLocalizer(preferences: preferences)
            let alert = NSAlert(error: error)
            alert.messageText = localizer.text(.launchAtLoginFailed)
            alert.icon = NSApp.applicationIconImage
            alert.runModal()
            syncLaunchAtLoginPreference()
        }

        updateLaunchAtLoginMenuItem()
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
