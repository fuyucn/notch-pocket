import AppKit

/// Thin `NSEvent` monitor wrapper that registers one global + one local
/// monitor with the same mask and handler. The global monitor observes
/// events in other apps (requires Input Monitoring permission in TCC);
/// the local monitor observes events in our own app's windows (no TCC
/// permission required). Callers get events from either source.
@MainActor
public final class EventMonitor {
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private let mask: NSEvent.EventTypeMask
    private let handler: (NSEvent?) -> Void

    public init(mask: NSEvent.EventTypeMask, handler: @escaping (NSEvent?) -> Void) {
        self.mask = mask
        self.handler = handler
    }

    public func start() {
        guard globalMonitor == nil else { return }
        let global = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated {
                self?.handler(event)
            }
        }
        globalMonitor = global
        let local = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated {
                self?.handler(event)
            }
            return event
        }
        localMonitor = local
    }

    public func stop() {
        if let g = globalMonitor {
            NSEvent.removeMonitor(g)
            globalMonitor = nil
        }
        if let l = localMonitor {
            NSEvent.removeMonitor(l)
            localMonitor = nil
        }
    }
}
