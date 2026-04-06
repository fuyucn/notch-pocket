import Testing
import Foundation
@testable import DropZoneLib

@Suite("SettingsManager Tests")
@MainActor
struct SettingsManagerTests {

    /// Create a SettingsManager backed by a volatile (in-memory) UserDefaults suite
    /// so tests don't pollute real preferences.
    private func makeManager() -> SettingsManager {
        let suiteName = "com.dropzone.test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return SettingsManager(defaults: defaults)
    }

    // MARK: - Defaults

    @Test("Default values are correct")
    func defaultValues() {
        let manager = makeManager()
        #expect(manager.launchAtLogin == false)
        #expect(manager.animationSpeed == .normal)
        #expect(manager.maxShelfItems == 50)
        #expect(manager.maxStorageBytes == 2_147_483_648)
        #expect(manager.expiryInterval == 3600)
        #expect(manager.soundEffectsEnabled == true)
        #expect(manager.showOnAllDisplays == false)
    }

    // MARK: - Launch at Login

    @Test("Set launch at login persists value")
    func launchAtLoginPersists() {
        let manager = makeManager()
        manager.launchAtLogin = true
        #expect(manager.launchAtLogin == true)
        manager.launchAtLogin = false
        #expect(manager.launchAtLogin == false)
    }

    // MARK: - Animation Speed

    @Test("Animation speed round-trips through raw value")
    func animationSpeedRoundTrip() {
        let manager = makeManager()
        for speed in AnimationSpeed.allCases {
            manager.animationSpeed = speed
            #expect(manager.animationSpeed == speed)
        }
    }

    @Test("AnimationSpeed labels are non-empty")
    func animationSpeedLabels() {
        for speed in AnimationSpeed.allCases {
            #expect(!speed.label.isEmpty)
        }
    }

    @Test("AnimationSpeed duration multipliers")
    func animationSpeedMultipliers() {
        #expect(AnimationSpeed.slow.durationMultiplier > AnimationSpeed.normal.durationMultiplier)
        #expect(AnimationSpeed.normal.durationMultiplier > AnimationSpeed.fast.durationMultiplier)
        #expect(AnimationSpeed.fast.durationMultiplier > 0)
    }

    // MARK: - Max Shelf Items

    @Test("Max shelf items clamps to valid range")
    func maxShelfItemsClamped() {
        let manager = makeManager()

        manager.maxShelfItems = 5 // Below minimum (10)
        #expect(manager.maxShelfItems == 10)

        manager.maxShelfItems = 300 // Above maximum (200)
        #expect(manager.maxShelfItems == 200)

        manager.maxShelfItems = 100 // Within range
        #expect(manager.maxShelfItems == 100)
    }

    // MARK: - Max Storage Bytes

    @Test("Max storage bytes clamps to valid range")
    func maxStorageBytesClamped() {
        let manager = makeManager()

        manager.maxStorageBytes = 100 // Below minimum (500 MB)
        #expect(manager.maxStorageBytes == 500_000_000)

        manager.maxStorageBytes = 20_000_000_000 // Above maximum (10 GB)
        #expect(manager.maxStorageBytes == 10_000_000_000)

        manager.maxStorageBytes = 3_000_000_000 // Within range
        #expect(manager.maxStorageBytes == 3_000_000_000)
    }

    // MARK: - Expiry Interval

    @Test("Expiry interval clamps to valid range")
    func expiryIntervalClamped() {
        let manager = makeManager()

        manager.expiryInterval = 60 // Below minimum (900s = 15 min)
        #expect(manager.expiryInterval == 900)

        manager.expiryInterval = 100_000 // Above maximum (86400s = 24h)
        #expect(manager.expiryInterval == 86400)

        manager.expiryInterval = 1800 // Within range (30 min)
        #expect(manager.expiryInterval == 1800)
    }

    // MARK: - Sound Effects

    @Test("Sound effects toggle")
    func soundEffectsToggle() {
        let manager = makeManager()
        #expect(manager.soundEffectsEnabled == true)
        manager.soundEffectsEnabled = false
        #expect(manager.soundEffectsEnabled == false)
    }

    // MARK: - Show On All Displays

    @Test("Show on all displays toggle")
    func showOnAllDisplaysToggle() {
        let manager = makeManager()
        #expect(manager.showOnAllDisplays == false)
        manager.showOnAllDisplays = true
        #expect(manager.showOnAllDisplays == true)
    }

    // MARK: - Callback

    @Test("onSettingsChanged fires on property change")
    func callbackFires() {
        let manager = makeManager()
        nonisolated(unsafe) var callCount = 0
        manager.onSettingsChanged = { callCount += 1 }

        manager.maxShelfItems = 30
        manager.expiryInterval = 1800
        manager.animationSpeed = .fast
        #expect(callCount == 3)
    }

    // MARK: - Labels

    @Test("Expiry interval label formatting")
    func expiryIntervalLabel() {
        let manager = makeManager()

        manager.expiryInterval = 900 // 15 min
        #expect(manager.expiryIntervalLabel == "15 min")

        manager.expiryInterval = 3600 // 1 hour
        #expect(manager.expiryIntervalLabel == "1 hour")

        manager.expiryInterval = 7200 // 2 hours
        #expect(manager.expiryIntervalLabel == "2 hours")

        manager.expiryInterval = 5400 // 1h 30m
        #expect(manager.expiryIntervalLabel == "1h 30m")
    }

    @Test("Max storage label formatting")
    func maxStorageLabel() {
        let manager = makeManager()

        manager.maxStorageBytes = 2_000_000_000 // 2 GB
        #expect(manager.maxStorageLabel == "2.0 GB")

        manager.maxStorageBytes = 500_000_000 // 500 MB
        #expect(manager.maxStorageLabel == "500 MB")
    }

    // MARK: - Persistence across instances

    @Test("Settings persist across manager instances with same suite")
    func persistenceAcrossInstances() {
        let suiteName = "com.dropzone.test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!

        let manager1 = SettingsManager(defaults: defaults)
        manager1.maxShelfItems = 77
        manager1.animationSpeed = .fast
        manager1.expiryInterval = 1800

        // Create a new instance with the same backing store
        let manager2 = SettingsManager(defaults: defaults)
        #expect(manager2.maxShelfItems == 77)
        #expect(manager2.animationSpeed == .fast)
        #expect(manager2.expiryInterval == 1800)
    }

    @Test("Invalid animation speed raw value falls back to normal")
    func invalidAnimationSpeedFallback() {
        let suiteName = "com.dropzone.test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set(999, forKey: "animationSpeed") // Invalid raw value
        let manager = SettingsManager(defaults: defaults)
        #expect(manager.animationSpeed == .normal)
    }

    @Test("Callback does NOT fire on property read")
    func callbackDoesNotFireOnRead() {
        let manager = makeManager()
        nonisolated(unsafe) var callCount = 0
        manager.onSettingsChanged = { callCount += 1 }

        // Reading properties should not trigger callback
        _ = manager.maxShelfItems
        _ = manager.expiryInterval
        _ = manager.animationSpeed
        _ = manager.soundEffectsEnabled
        _ = manager.launchAtLogin
        #expect(callCount == 0)
    }

    @Test("Expiry label for 24 hours (max)")
    func expiryLabelMax() {
        let manager = makeManager()
        manager.expiryInterval = 86400 // 24 hours
        #expect(manager.expiryIntervalLabel == "24 hours")
    }

    @Test("Expiry label for exact boundary values")
    func expiryLabelBoundaries() {
        let manager = makeManager()

        manager.expiryInterval = 900 // min = 15 min
        #expect(manager.expiryIntervalLabel == "15 min")

        manager.expiryInterval = 3660 // 1h 1m
        #expect(manager.expiryIntervalLabel == "1h 1m")
    }

    @Test("Max storage label for 10 GB (max)")
    func maxStorageLabelMax() {
        let manager = makeManager()
        manager.maxStorageBytes = 10_000_000_000
        #expect(manager.maxStorageLabel == "10.0 GB")
    }

    @Test("Setting maxShelfItems to boundary values")
    func maxShelfItemsBoundary() {
        let manager = makeManager()

        manager.maxShelfItems = 10 // exact minimum
        #expect(manager.maxShelfItems == 10)

        manager.maxShelfItems = 200 // exact maximum
        #expect(manager.maxShelfItems == 200)
    }

    @Test("Setting maxStorageBytes to boundary values")
    func maxStorageBytesBoundary() {
        let manager = makeManager()

        manager.maxStorageBytes = 500_000_000 // exact minimum
        #expect(manager.maxStorageBytes == 500_000_000)

        manager.maxStorageBytes = 10_000_000_000 // exact maximum
        #expect(manager.maxStorageBytes == 10_000_000_000)
    }

    @Test("Setting expiryInterval to boundary values")
    func expiryIntervalBoundary() {
        let manager = makeManager()

        manager.expiryInterval = 900 // exact minimum
        #expect(manager.expiryInterval == 900)

        manager.expiryInterval = 86400 // exact maximum
        #expect(manager.expiryInterval == 86400)
    }

    @Test("Each AnimationSpeed has unique duration multiplier")
    func animationSpeedUniqueness() {
        let multipliers = AnimationSpeed.allCases.map(\.durationMultiplier)
        #expect(Set(multipliers).count == multipliers.count) // All unique
    }
}
