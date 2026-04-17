import SwiftUI

/// SwiftUI settings window for DropZone preferences.
///
/// Provides controls for:
/// - Launch at login
/// - Animation speed
/// - Max shelf items
/// - Max storage size
/// - Auto-expiry interval
/// - Sound effects toggle
@MainActor
public struct SettingsView: View {
    private let settingsManager: SettingsManager

    @State private var launchAtLogin: Bool
    @State private var animationSpeed: AnimationSpeed
    @State private var maxShelfItems: Double
    @State private var expiryMinutes: Double
    @State private var maxStorageGB: Double
    @State private var soundEffects: Bool
    @State private var inputMonitoringStatus: PermissionStatus = .undetermined
    @State private var permissionsManager = PermissionsManager()

    public init(settingsManager: SettingsManager) {
        self.settingsManager = settingsManager
        _launchAtLogin = State(initialValue: settingsManager.launchAtLogin)
        _animationSpeed = State(initialValue: settingsManager.animationSpeed)
        _maxShelfItems = State(initialValue: Double(settingsManager.maxShelfItems))
        _expiryMinutes = State(initialValue: settingsManager.expiryInterval / 60.0)
        _maxStorageGB = State(initialValue: Double(settingsManager.maxStorageBytes) / 1_000_000_000.0)
        _soundEffects = State(initialValue: settingsManager.soundEffectsEnabled)
    }

    public var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        settingsManager.launchAtLogin = newValue
                    }

                Toggle("Sound effects", isOn: $soundEffects)
                    .onChange(of: soundEffects) { _, newValue in
                        settingsManager.soundEffectsEnabled = newValue
                    }
            }

            Section("Animation") {
                Picker("Animation speed", selection: $animationSpeed) {
                    ForEach(AnimationSpeed.allCases, id: \.self) { speed in
                        Text(speed.label).tag(speed)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: animationSpeed) { _, newValue in
                    settingsManager.animationSpeed = newValue
                }
            }

            Section("Storage") {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Max shelf items")
                        Spacer()
                        Text("\(Int(maxShelfItems))")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $maxShelfItems, in: 10...200, step: 10)
                        .onChange(of: maxShelfItems) { _, newValue in
                            settingsManager.maxShelfItems = Int(newValue)
                        }
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Max storage")
                        Spacer()
                        Text(storageLabel)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $maxStorageGB, in: 0.5...10.0, step: 0.5)
                        .onChange(of: maxStorageGB) { _, newValue in
                            settingsManager.maxStorageBytes = Int64(newValue * 1_000_000_000)
                        }
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Auto-expire after")
                        Spacer()
                        Text(expiryLabel)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $expiryMinutes, in: 15...1440, step: 15)
                        .onChange(of: expiryMinutes) { _, newValue in
                            settingsManager.expiryInterval = newValue * 60.0
                        }
                }
            }
            Section("Permissions") {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Input Monitoring")
                                .font(.system(size: 13, weight: .medium))
                            Text("Required to detect when you hover or drag files near the notch.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        switch inputMonitoringStatus {
                        case .granted:
                            Text("Granted")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.green)
                        case .denied, .undetermined:
                            Button("Grant…") {
                                if !permissionsManager.requestInputMonitoring() {
                                    permissionsManager.openInputMonitoringSettings()
                                }
                                // Re-check after a short delay
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    inputMonitoringStatus = permissionsManager.inputMonitoringStatus
                                }
                            }
                            .controlSize(.small)
                        }
                    }
                    .padding(.vertical, 4)
                }
        }
        .formStyle(.grouped)
        .frame(width: 380, height: 400)
        .fixedSize()
        .onAppear {
            inputMonitoringStatus = permissionsManager.inputMonitoringStatus
        }
    }

    private var storageLabel: String {
        if maxStorageGB >= 1.0 {
            return String(format: "%.1f GB", maxStorageGB)
        }
        return String(format: "%.0f MB", maxStorageGB * 1000)
    }

    private var expiryLabel: String {
        let mins = Int(expiryMinutes)
        if mins < 60 {
            return "\(mins) min"
        }
        let hours = mins / 60
        let rem = mins % 60
        if rem == 0 {
            return "\(hours) hour\(hours == 1 ? "" : "s")"
        }
        return "\(hours)h \(rem)m"
    }
}
