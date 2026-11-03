import AppKit
import SwiftUI

/// Settings in an AppKit window with the standard toolbar tabs, so the Dock menu and the
/// menu bar item can open it (SwiftUI's Settings scene can't be opened from AppKit). Same
/// design as SnagAnything's: each pane opens at its natural height capped to the screen,
/// scrolls when it holds more, and the window can be dragged bigger — a size it keeps.
@MainActor
final class SettingsWindow: NSObject, NSWindowDelegate {
    static let shared = SettingsWindow()

    /// Set at launch, before the window is first shown.
    var desks: DeskTracker!
    var launchAtLogin: LaunchAtLogin!

    private var window: NSWindow?

    func show(tab: String? = nil) {
        if window == nil {
            let tabs = SettingsTabs(desks: desks, launchAtLogin: launchAtLogin)
            let window = NSWindow(contentViewController: tabs)
            window.styleMask = [.titled, .closable, .resizable]
            window.contentMinSize = SettingsTabs.minimumSize
            window.toolbarStyle = .preference
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            self.window = window
        }
        if let tab, let tabs = window?.contentViewController as? SettingsTabs { tabs.select(tab) }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        // After an update the user didn't see the notes for, what changed.
        if let window { WhatsNew.shared.present(on: window) }
    }

    /// This version's notes, because the user asked (What's New… in General).
    func showWhatsNew() {
        show()
        if let window { WhatsNew.shared.present(on: window, asked: true) }
    }

    var debugWindow: NSWindow? { window }

    /// A size the user dragged to is kept for every pane, and next time.
    func windowDidEndLiveResize(_ notification: Notification) {
        guard let window else { return }
        SettingsTabs.chosenSize = window.contentRect(forFrameRect: window.frame).size
    }

    /// Moved to another screen: the pane fits that one.
    func windowDidChangeScreen(_ notification: Notification) {
        (window?.contentViewController as? SettingsTabs)?.refit()
    }
}

/// One toolbar item per pane. Each pane lives in its own file (GeneralSettings.swift,
/// DesksSettings.swift, …).
@MainActor
final class SettingsTabs: NSTabViewController {
    init(desks: DeskTracker, launchAtLogin: LaunchAtLogin) {
        super.init(nibName: nil, bundle: nil)
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil,
                                               queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.refit() } }
        tabStyle = .toolbar
        transitionOptions = [.crossfade, .allowUserInteraction]
        add("General", "gearshape", GeneralSettings(launchAtLogin: launchAtLogin))
        add("Desks", "display.2", DesksSettings(desks: desks))
        add("Palette", "square.grid.3x1.below.line.grid.1x2", PaletteSettings(desks: desks))
        add("Layouts", "rectangle.split.3x1", LayoutsSettings(desks: desks))
        add("Shortcuts", "keyboard", ShortcutsSettings())
    }

    required init?(coder: NSCoder) { fatalError() }

    private func add(_ title: String, _ symbol: String, _ content: some View) {
        let view = VStack(spacing: 0) {
            content
            // The round Help button in the corner, as macOS does, open at this pane's page.
            HStack {
                Spacer()
                HelpButton(topic: Help.topic(forSettingsTab: title)).fixedSize()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
        // Letting SwiftUI size the window to a Form's full height crashed once a pane grew
        // taller than the screen (AppKit clamped, SwiftUI asked again, AppKit aborted), so
        // the window is sized here and the pane fills whatever size it gets.
        let hosting = NSHostingController(rootView: view.frame(minWidth: Self.minimumSize.width, maxWidth: .infinity,
                                                               maxHeight: .infinity))
        hosting.sizingOptions = []
        hosting.title = title
        let item = NSTabViewItem(viewController: hosting)
        item.label = title
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        addTabViewItem(item)
        naturalHeight[item] = { NSHostingView(rootView: view.frame(width: Self.width)).fittingSize.height }
        fit(item)
    }

    /// Measures a pane on a throwaway hosting view, so the window never follows SwiftUI.
    private var naturalHeight: [NSTabViewItem: () -> CGFloat] = [:]

    /// The tallest a pane opens at on any screen; the rest scrolls.
    static let tallest: CGFloat = 660
    /// The width panes are laid out for, and the smallest the window can be dragged to.
    static let width: CGFloat = 620
    static let minimumSize = NSSize(width: width, height: 280)

    /// The content size the user last dragged the window to (per Mac, not synced).
    static var chosenSize: NSSize? {
        get { UserDefaults.standard.string(forKey: "settings.contentSize").map(NSSizeFromString) }
        set { UserDefaults.standard.set(newValue.map(NSStringFromSize), forKey: "settings.contentSize") }
    }

    @discardableResult
    private func fit(_ item: NSTabViewItem) -> NSSize? {
        guard let height = naturalHeight[item]?() else { return nil }
        let screen = (isViewLoaded ? view.window?.screen : nil) ?? NSScreen.main
        let available = (screen?.visibleFrame.height ?? 800) - 120
        var size = NSSize(width: Self.width, height: min(height, available, Self.tallest))
        if let chosen = Self.chosenSize {
            size = NSSize(width: max(chosen.width, Self.minimumSize.width),
                          height: min(max(chosen.height, Self.minimumSize.height), available))
        }
        item.viewController?.preferredContentSize = size
        return size
    }

    /// The shown pane fitted again, keeping the window's top where it is and all of it on screen.
    func refit() {
        guard isViewLoaded, let window = view.window, selectedTabViewItemIndex >= 0,
              let size = fit(tabViewItems[selectedTabViewItemIndex]) else { return }
        var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: size))
        frame.origin = NSPoint(x: window.frame.minX, y: window.frame.maxY - frame.height)
        if let visible = window.screen?.visibleFrame {
            frame.origin.y = max(min(frame.origin.y, visible.maxY - frame.height), visible.minY)
            frame.origin.x = max(min(frame.origin.x, visible.maxX - frame.width), visible.minX)
        }
        window.setFrame(frame, display: true, animate: false)
    }

    override func tabView(_ tabView: NSTabView, willSelect tabViewItem: NSTabViewItem?) {
        if let tabViewItem { fit(tabViewItem) }
        super.tabView(tabView, willSelect: tabViewItem)
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        selectionChanged()
    }

    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        selectionChanged()
    }

    func select(_ label: String) {
        if let index = tabViewItems.firstIndex(where: { $0.label == label }) { selectedTabViewItemIndex = index }
    }

    private func selectionChanged() {
        view.window?.title = tabViewItems[selectedTabViewItemIndex].label
    }
}

/// A small gray explanation under a setting.
struct Caption: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}
