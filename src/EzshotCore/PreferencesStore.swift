import Foundation

public final class PreferencesStore {
    public static let autoCopyAfterCaptureKey = "autoCopyAfterCapture"
    public static let captureDelaySecondsKey = "captureDelaySeconds"
    public static let languageModeKey = "languageMode"
    public static let appearanceModeKey = "appearanceMode"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var autoCopyAfterCapture: Bool {
        get {
            guard defaults.object(forKey: Self.autoCopyAfterCaptureKey) != nil else {
                return true
            }
            return defaults.bool(forKey: Self.autoCopyAfterCaptureKey)
        }
        set {
            defaults.set(newValue, forKey: Self.autoCopyAfterCaptureKey)
        }
    }

    public var captureDelaySeconds: Double {
        get {
            guard defaults.object(forKey: Self.captureDelaySecondsKey) != nil else {
                return 0
            }
            return max(0, defaults.double(forKey: Self.captureDelaySecondsKey))
        }
        set {
            defaults.set(max(0, newValue), forKey: Self.captureDelaySecondsKey)
        }
    }

    public var languageMode: String {
        get {
            defaults.string(forKey: Self.languageModeKey) ?? "system"
        }
        set {
            defaults.set(newValue, forKey: Self.languageModeKey)
        }
    }

    public var appearanceMode: String {
        get {
            defaults.string(forKey: Self.appearanceModeKey) ?? "system"
        }
        set {
            defaults.set(newValue, forKey: Self.appearanceModeKey)
        }
    }
}
