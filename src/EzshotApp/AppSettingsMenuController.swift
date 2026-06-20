import AppKit
import EzshotCore

@MainActor
final class AppSettingsMenuController: NSObject {
    private let preferences: PreferencesStore
    private let onChange: () -> Void

    init(preferences: PreferencesStore, onChange: @escaping () -> Void) {
        self.preferences = preferences
        self.onChange = onChange
        super.init()
    }

    func makeLanguageMenu(localizer: AppLocalizer) -> NSMenu {
        let menu = NSMenu(title: localizer.text(.language))
        addLanguageItem(.system, title: localizer.text(.system), to: menu)
        addLanguageItem(.traditionalChinese, title: localizer.text(.traditionalChinese), to: menu)
        addLanguageItem(.english, title: localizer.text(.english), to: menu)
        return menu
    }

    func makeAppearanceMenu(localizer: AppLocalizer) -> NSMenu {
        let menu = NSMenu(title: localizer.text(.appearance))
        addAppearanceItem(.system, title: localizer.text(.system), to: menu)
        addAppearanceItem(.light, title: localizer.text(.light), to: menu)
        addAppearanceItem(.dark, title: localizer.text(.dark), to: menu)
        return menu
    }

    static func applyAppearance(preferences: PreferencesStore) {
        switch AppAppearanceMode(rawValue: preferences.appearanceMode) ?? .system {
        case .system:
            NSApp.appearance = nil
        case .light:
            NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    private func addLanguageItem(_ language: AppLanguage, title: String, to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: #selector(selectLanguage(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = language.rawValue
        item.state = preferences.languageMode == language.rawValue ? .on : .off
        menu.addItem(item)
    }

    private func addAppearanceItem(_ appearance: AppAppearanceMode, title: String, to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: #selector(selectAppearance(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = appearance.rawValue
        item.state = preferences.appearanceMode == appearance.rawValue ? .on : .off
        menu.addItem(item)
    }

    @objc private func selectLanguage(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String else {
            return
        }

        preferences.languageMode = value
        onChange()
    }

    @objc private func selectAppearance(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String else {
            return
        }

        preferences.appearanceMode = value
        Self.applyAppearance(preferences: preferences)
        onChange()
    }
}
