import AppKit
import GridLockKit
import Observation

/// Knows which desk the Mac is at: watches the displays, waits for them to settle, and picks
/// (or creates) the desk for that set. Everything that needs a display's grid or palette asks here.
@Observable
@MainActor
final class DeskTracker {
    let store: DeskStore
    /// The desk the displays settled on; nil until the first settle at launch (about 2 s).
    private(set) var currentDeskID: UUID?
    /// The displays connected now, refreshed on every change (not only once settled), so an
    /// overlay always goes on a display that exists.
    private(set) var live: [LiveDisplay] = []

    /// A desk seen for the first time (not the very first desk on a fresh install).
    @ObservationIgnored var onNewDesk: ((Desk) -> Void)?

    @ObservationIgnored private var tracker = SettleTracker()
    @ObservationIgnored private var settleTimer: Timer?
    @ObservationIgnored private var tokens: [NSObjectProtocol] = []

    init(store: DeskStore) {
        self.store = store
    }

    var currentDesk: Desk? { store.desk(id: currentDeskID) }

    func start() {
        func on(_ center: NotificationCenter, _ name: Notification.Name, _ reason: String) {
            tokens.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.displaysChanged(reason) }
            })
        }
        on(.default, NSApplication.didChangeScreenParametersNotification, "screen parameters")
        on(NSWorkspace.shared.notificationCenter, NSWorkspace.didWakeNotification, "wake")
        on(NSWorkspace.shared.notificationCenter, NSWorkspace.screensDidWakeNotification, "screens woke")
        displaysChanged("launch")
        store.recoverFromCloudIfEmpty { [weak self] in
            self?.tracker = SettleTracker()
            self?.displaysChanged("recovered from iCloud")
        }
    }

    /// The settings for a display at the current desk. A display the desk doesn't know yet
    /// (connected after it settled, mid-change) gets suggestions until it settles.
    func settings(for display: LiveDisplay) -> DisplaySettings {
        store.library.settings(forDisplay: display.key, size: display.bounds.size, atDesk: currentDeskID)
    }

    func display(holding frame: CGRect) -> LiveDisplay? {
        if live.isEmpty { live = DisplayCatalog.current() }
        return LiveDisplay.index(holding: frame, in: live).map { live[$0] }
    }

    private func displaysChanged(_ reason: String) {
        live = DisplayCatalog.current()
        tracker.reset()
        settleTimer?.invalidate()
        sample()
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
        RunLoop.main.add(timer, forMode: .common)
        settleTimer = timer
        Diagnostics.note("displays changed (\(reason)); waiting for them to settle")
    }

    private func sample() {
        let displays = DisplayCatalog.current()
        live = displays
        let signature = DeskSignature.make(displays.map(\.key))
        guard case let .settled(_, changed, _)? = tracker.sample(signature) else { return }
        settleTimer?.invalidate()
        settleTimer = nil
        settled(displays, signature: signature, changed: changed)
    }

    private func settled(_ displays: [LiveDisplay], signature: String, changed: Bool) {
        let records = displays.map(\.record)
        if var desk = store.library.desk(withSignature: signature) {
            desk.displays = records
            desk.lastUsed = Date()
            // A display added to the desk's set by an older version, say: give it settings.
            for display in displays where desk.settings[display.key] == nil {
                desk.settings[display.key] = store.library.seededSettings(for: [display])[display.key]
            }
            store.update(desk)
            currentDeskID = desk.id
            Diagnostics.note("settled on desk \"\(desk.name)\" [\(signature)] changed=\(changed)")
        } else {
            let isFirst = store.library.desks.isEmpty
            let desk = Desk(name: store.library.uniqueName(DeskSignature.defaultName(for: records)), signature: signature,
                            displays: records, settings: store.library.seededSettings(for: displays))
            store.add(desk)
            currentDeskID = desk.id
            Diagnostics.note("new desk \"\(desk.name)\" [\(signature)]")
            if !isFirst { onNewDesk?(desk) }
        }
    }

    /// For the debug hook: what the tracker sees.
    func dump() -> String {
        var lines = ["desk: \(currentDesk?.name ?? "none") [\(currentDesk?.signature ?? "")]"]
        for d in live {
            let s = settings(for: d)
            lines.append("  \(d.key) \"\(d.name)\" bounds=\(d.bounds) visible=\(d.visible) grid=\(s.grid.columns)×\(s.grid.rows) gap=\(s.grid.gap) margin=\(s.grid.margin) palette=\(s.palette.count)")
        }
        return lines.joined(separator: "\n")
    }
}
