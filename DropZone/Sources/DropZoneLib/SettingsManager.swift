import AppKit
import ServiceManagement

/// Keys for UserDefaults persistence.
private enum SettingsKey {
    static let launchAtLogin = "launchAtLogin"
    static let animationSpeed = "animationSpeed"
    static let maxShelfItems = "maxShelfItems"
    static let maxStorageBytes = "maxStorageBytes"
    static let expiryInterval = "expiryInterval"
    static let soundEffectsEnabled = "soundEffectsEnabled"
    static let showOnAllDisplays = "showOnAllDisplays"
}

/// Animation speed presets.
public enum AnimationSpeed: Int, CaseIterable, Sendable {
    case slow = 0
    case normal = 1
    case fast = 2

    public var label: String {
        switch self {
        case .slow: "Slow"
        case .normal: "Normal"
        case .fast: "Fast"
        }
    }

    /// Multiplier applied to base animation durations.
    /// Lower = faster.
    public var durationMultiplier: Double {
        switch self {
        case .slow: 1.5
        case .normal: 1.0
        case .fast: 0.5
        }
    }
}

/// Centralized settings persistence using UserDefaults.
///
/// Provides typed accessors for all app preferences with sensible defaults.
/// Changes are published via `onSettingsChanged` so dependent components
/// can react (e.g. FileShelfManager updating its limits).
@MainActor
public final class SettingsManager {
    private let defaults: UserDefaults

    /// Fired when any setting changes. Consumers should re-read the properties they care about.
    public var onSettingsChanged: (@MainActor @Sendable () -> Void)?

    // MARK: - Init

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        registerDefaults()
    }

    private func registerDefaults() {
        defaults.register(defaults: [
            SettingsKey.launchAtLogin: false,
            SettingsKey.animationSpeed: AnimationSpeed.normal.rawValue,
            SettingsKey.maxShelfItems: 50,
            SettingsKey.maxStorageBytes: Int64(2_147_483_648), // 2 GB
            SettingsKey.expiryInterval: 3600.0, // 1 hour
            SettingsKey.soundEffectsEnabled: true,
            SettingsKey.showOnAllDisplays: false,
        ])
    }

    // MARK: - Launch at Login

    public var launchAtLogin: Bool {
        get { defaults.bool(forKey: SettingsKey.launchAtLogin) }
        set {
            defaults.set(newValue, forKey: SettingsKey.launchAtLogin)
            applyLaunchAtLogin(newValue)
            notifyChanged()
        }
    }

    private func applyLaunchAtLogin(_ enabled: Bool) {
        if #available(macOS 14.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                // SMAppService may fail if not running from /Applications.
                // Silently ignore — the toggle will still persist the preference.
            }
        }
    }

    // MARK: - Animation Speed

    public var animationSpeed: AnimationSpeed {
        get {
            let raw = defaults.integer(forKey: SettingsKey.animationSpeed)
            return AnimationSpeed(rawValue: raw) ?? .normal
        }
        set {
            defaults.set(newValue.rawValue, forKey: SettingsKey.animationSpeed)
            notifyChanged()
        }
    }

    // MARK: - Max Shelf Items

    /// Range: 10–200.
    public var maxShelfItems: Int {
        get { defaults.integer(forKey: SettingsKey.maxShelfItems) }
        set {
            let clamped = min(max(newValue, 10), 200)
            defaults.set(clamped, forKey: SettingsKey.maxShelfItems)
            notifyChanged()
        }
    }

    // MARK: - Max Storage Bytes

    /// Range: 500 MB – 10 GB.
    public var maxStorageBytes: Int64 {
        get {
            let value = defaults.object(forKey: SettingsKey.maxStorageBytes) as? Int64
            return value ?? 2_147_483_648
        }
        set {
            let clamped = min(max(newValue, 500_000_000), 10_000_000_000)
            defaults.set(clamped, forKey: SettingsKey.maxStorageBytes)
            notifyChanged()
        }
    }

    // MARK: - Expiry Interval

    /// Range: 15 minutes (900s) – 24 hours (86400s).
    public var expiryInterval: TimeInterval {
        get { defaults.double(forKey: SettingsKey.expiryInterval) }
        set {
            let clamped = min(max(newValue, 900), 86400)
            defaults.set(clamped, forKey: SettingsKey.expiryInterval)
            notifyChanged()
        }
    }

    // MARK: - Sound Effects

    public var soundEffectsEnabled: Bool {
        get { defaults.bool(forKey: SettingsKey.soundEffectsEnabled) }
        set {
            defaults.set(newValue, forKey: SettingsKey.soundEffectsEnabled)
            notifyChanged()
        }
    }

    // MARK: - Show On All Displays

    public var showOnAllDisplays: Bool {
        get { defaults.bool(forKey: SettingsKey.showOnAllDisplays) }
        set {
            defaults.set(newValue, forKey: SettingsKey.showOnAllDisplays)
            notifyChanged()
        }
    }

    // MARK: - Convenience

    /// Formatted string for the current expiry interval.
    public var expiryIntervalLabel: String {
        let minutes = Int(expiryInterval / 60)
        if minutes < 60 {
            return "\(minutes) min"
        }
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        if remainingMinutes == 0 {
            return "\(hours) hour\(hours == 1 ? "" : "s")"
        }
        return "\(hours)h \(remainingMinutes)m"
    }

    /// Formatted string for the current max storage.
    public var maxStorageLabel: String {
        let gb = Double(maxStorageBytes) / 1_000_000_000
        if gb >= 1.0 {
            return String(format: "%.1f GB", gb)
        }
        let mb = Double(maxStorageBytes) / 1_000_000
        return String(format: "%.0f MB", mb)
    }

    // MARK: - Private

    private func notifyChanged() {
        onSettingsChanged?()
    }
}
