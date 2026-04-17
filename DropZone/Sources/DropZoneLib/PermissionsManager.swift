import AppKit
import IOKit.hid

/// Status of a system-level privacy permission.
public enum PermissionStatus: Sendable, Equatable {
    /// Permission has been granted.
    case granted
    /// Permission has been denied or never requested.
    case denied
    /// The OS has not yet decided (first launch, system hasn't shown a prompt yet).
    case undetermined
}

/// Queries and requests macOS privacy permissions needed by this app.
///
/// Currently only covers Input Monitoring (needed for global `mouseMoved` /
/// `leftMouseDragged` event monitors used to drive hover-based pre-activation
/// and drag detection).
@MainActor
public final class PermissionsManager {
    public init() {}

    // MARK: - Input Monitoring

    /// Non-prompting check of current Input Monitoring status.
    public var inputMonitoringStatus: PermissionStatus {
        let result = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
        switch result {
        case kIOHIDAccessTypeGranted: return .granted
        case kIOHIDAccessTypeDenied: return .denied
        case kIOHIDAccessTypeUnknown: return .undetermined
        default: return .undetermined
        }
    }

    /// Ask the system to prompt the user for Input Monitoring permission the
    /// first time. On subsequent calls (after user denied), this returns
    /// without a prompt — callers should fall back to `openInputMonitoringSettings()`.
    ///
    /// Returns `true` if the request was granted (possibly after prompt),
    /// `false` otherwise.
    @discardableResult
    public func requestInputMonitoring() -> Bool {
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    }

    /// Open System Settings directly to the Input Monitoring pane.
    public func openInputMonitoringSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!
        NSWorkspace.shared.open(url)
    }
}
