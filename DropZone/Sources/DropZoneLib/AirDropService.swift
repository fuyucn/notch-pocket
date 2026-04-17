import AppKit

/// Tiny wrapper around NSSharingService's AirDrop sender so views stay testable.
@MainActor
public enum AirDropService {
    public static func share(urls: [URL]) {
        guard !urls.isEmpty else { return }
        if let svc = NSSharingService(named: .sendViaAirDrop) {
            svc.perform(withItems: urls)
        }
    }

    /// True iff the system reports AirDrop sharing is possible for these URLs.
    public static func canShare(urls: [URL]) -> Bool {
        guard !urls.isEmpty else { return false }
        guard let svc = NSSharingService(named: .sendViaAirDrop) else { return false }
        return svc.canPerform(withItems: urls)
    }
}
