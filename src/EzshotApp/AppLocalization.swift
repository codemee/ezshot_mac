import AppKit
import EzshotCore

enum AppLanguage: String, CaseIterable {
    case system
    case english = "en"
    case traditionalChinese = "zh-Hant"
}

enum AppAppearanceMode: String, CaseIterable {
    case system
    case light
    case dark
}

struct AppLocalizer {
    private let language: AppLanguage

    init(preferences: PreferencesStore) {
        let mode = AppLanguage(rawValue: preferences.languageMode) ?? .system
        if mode == .system {
            language = Self.systemLanguage()
        } else {
            language = mode
        }
    }

    func text(_ key: Key) -> String {
        switch language {
        case .traditionalChinese:
            zhHant[key] ?? en[key] ?? key.rawValue
        case .system, .english:
            en[key] ?? key.rawValue
        }
    }

    static func systemLanguage() -> AppLanguage {
        let preferred = Locale.preferredLanguages.first ?? ""
        return preferred.hasPrefix("zh-Hant") || preferred.hasPrefix("zh-TW") || preferred.hasPrefix("zh-HK")
            ? .traditionalChinese
            : .english
    }

    enum Key: String {
        case captureSelection
        case captureActiveWindow
        case pickWindow
        case showScreenshots
        case autoCopy
        case delay
        case language
        case appearance
        case system
        case english
        case traditionalChinese
        case light
        case dark
        case quit
        case save
        case saveAs
        case file
        case window
        case copyEditedImage
        case showPreviousTab
        case showNextTab
        case undo
        case line
        case arrow
        case mosaic
        case style
        case tools
        case lineStyle
        case emptyTitle
        case emptyMessage
        case seconds
        case off
        case closeUnsavedScreenshot
        case closeUnsavedScreenshots
        case unsavedScreenshotsDiscarded
        case discard
        case cancel
    }

    private var en: [Key: String] {
        [
            .captureSelection: "Capture Selection",
            .captureActiveWindow: "Capture Active Window",
            .pickWindow: "Pick Window to Capture",
            .showScreenshots: "Show Screenshots",
            .autoCopy: "Auto Copy After Capture",
            .delay: "Capture Delay",
            .language: "Language",
            .appearance: "Appearance",
            .system: "System",
            .english: "English",
            .traditionalChinese: "Traditional Chinese",
            .light: "Light",
            .dark: "Dark",
            .quit: "Quit Ezshot",
            .save: "Save",
            .saveAs: "Save As...",
            .file: "File",
            .window: "Window",
            .copyEditedImage: "Copy Edited Image",
            .showPreviousTab: "Show Previous Tab",
            .showNextTab: "Show Next Tab",
            .undo: "Undo",
            .line: "Line",
            .arrow: "Arrow",
            .mosaic: "Mosaic",
            .style: "Style",
            .tools: "Tools",
            .lineStyle: "Line Color and Width",
            .emptyTitle: "Ezshot",
            .emptyMessage: "No screenshots yet",
            .seconds: "seconds",
            .off: "Off",
            .closeUnsavedScreenshot: "Close Unsaved Screenshot?",
            .closeUnsavedScreenshots: "Close %d Unsaved Screenshots?",
            .unsavedScreenshotsDiscarded: "Unsaved screenshots will be discarded.",
            .discard: "Discard",
            .cancel: "Cancel"
        ]
    }

    private var zhHant: [Key: String] {
        [
            .captureSelection: "截取區域",
            .captureActiveWindow: "截取焦點視窗",
            .pickWindow: "點選視窗截圖",
            .showScreenshots: "顯示截圖視窗",
            .autoCopy: "截圖後自動複製",
            .delay: "延遲截圖",
            .language: "語言",
            .appearance: "外觀",
            .system: "依系統設定",
            .english: "English",
            .traditionalChinese: "繁體中文",
            .light: "淺色",
            .dark: "深色",
            .quit: "結束 Ezshot",
            .save: "儲存",
            .saveAs: "另存新檔...",
            .file: "檔案",
            .window: "視窗",
            .copyEditedImage: "複製編修後圖片",
            .showPreviousTab: "顯示上一個頁籤",
            .showNextTab: "顯示下一個頁籤",
            .undo: "復原",
            .line: "線條",
            .arrow: "箭頭",
            .mosaic: "馬賽克",
            .style: "樣式",
            .tools: "工具",
            .lineStyle: "線條顏色與粗細",
            .emptyTitle: "Ezshot",
            .emptyMessage: "尚未有截圖",
            .seconds: "秒",
            .off: "關",
            .closeUnsavedScreenshot: "關閉未儲存的截圖？",
            .closeUnsavedScreenshots: "關閉 %d 張未儲存的截圖？",
            .unsavedScreenshotsDiscarded: "未儲存的截圖將會被放棄。",
            .discard: "放棄",
            .cancel: "取消"
        ]
    }
}
