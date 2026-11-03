import AppKit
import GridLockKit
import UserNotifications

/// "New desk: Dell P4317Q + Built-in", with Rename… and Settings… (S-022). Posted when the
/// displays settle on a set GridLock hasn't seen; the new desk already has settings borrowed
/// from the most similar desk.
///
/// The notification center has one delegate. When another part of GridLock already is it
/// (the updater), that delegate passes responses here first through `handle(_:)`.
@MainActor
final class NewDeskNotice: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NewDeskNotice()

    nonisolated static let categoryID = "newDesk"
    nonisolated static let renameAction = "rename"
    nonisolated static let settingsAction = "settings"
    private nonisolated static let deskKey = "desk"

    nonisolated static var category: UNNotificationCategory {
        UNNotificationCategory(identifier: categoryID, actions: [
            UNNotificationAction(identifier: renameAction, title: "Rename…", options: [.foreground]),
            UNNotificationAction(identifier: settingsAction, title: "Settings…", options: [.foreground]),
        ], intentIdentifiers: [])
    }

    /// A build run outside an app bundle has no notification center.
    private var center: UNUserNotificationCenter? {
        Bundle.main.bundleIdentifier == nil ? nil : UNUserNotificationCenter.current()
    }

    func start(desks: DeskTracker) {
        desks.onNewDesk = { [weak self] in self?.post($0) }
        if let center, center.delegate == nil { center.delegate = self }
    }

    func post(_ desk: Desk) {
        guard let center else { return }
        let content = UNMutableNotificationContent()
        content.title = "New desk: \(desk.name)"
        content.body = desk.name == desk.displayNames
            ? "Its grids and palettes start from your other desks."
            : "\(desk.displayNames). Its grids and palettes start from your other desks."
        content.categoryIdentifier = Self.categoryID
        content.userInfo = [Self.deskKey: desk.id.uuidString]
        let request = UNNotificationRequest(identifier: "newDesk-\(desk.id.uuidString)", content: content, trigger: nil)
        center.requestAuthorization(options: [.alert]) { granted, _ in
            guard granted else { return Diagnostics.note("new desk notice: notifications are off") }
            // Added to whatever categories are registered, never replacing them.
            center.getNotificationCategories { existing in
                let others = existing.filter { $0.identifier != Self.categoryID }
                center.setNotificationCategories(others.union([Self.category]))
                center.add(request) { error in
                    if let error { Diagnostics.note("new desk notice failed: \(error.localizedDescription)") }
                }
            }
        }
    }

    /// Acts on a click on a new-desk notification; false for anyone else's.
    @discardableResult
    nonisolated static func handle(_ response: UNNotificationResponse) -> Bool {
        let content = response.notification.request.content
        guard content.categoryIdentifier == categoryID else { return false }
        let id = (content.userInfo[deskKey] as? String).flatMap(UUID.init(uuidString:))
        let rename = response.actionIdentifier == renameAction
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                if let id { DeskSelection.shared.select(desk: id) }
                SettingsWindow.shared.show(tab: "Desks")
                if rename, let id { DeskSelection.shared.renaming = id }
            }
        }
        return true
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        Self.handle(response)
        completionHandler()
    }
}
