import AppKit
import GridLockKit

/// A borderless, non-activating panel covering part of a display, above ordinary windows:
/// the grid, the palette and the drop preview. Never activates GridLock, so the app whose
/// window is being placed stays in front.
@MainActor
final class OverlayPanel: NSPanel {
    /// Whether it takes keys (the grid does; the palette and preview never do).
    private let takesKeys: Bool

    init(takesKeys: Bool, clickThrough: Bool) {
        self.takesKeys = takesKeys
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        // Floating first: setting isFloatingPanel resets the level to .floating, which put
        // the grid and the palette under Notification Center's banners.
        isFloatingPanel = true
        level = .popUpMenu
        becomesKeyOnlyIfNeeded = !takesKeys
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = clickThrough
        isReleasedWhenClosed = false
        animationBehavior = .none
        // On every Space, over full-screen apps, left out of Mission Control and the window cycle.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        AppAppearance.followSystem(self)
    }

    /// Exactly where it's put: AppKit would otherwise push it below the menu bar, moving
    /// the palette (and its shadow margin) away from where the pointer is tracked.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }

    override var canBecomeKey: Bool { takesKeys }
    override var canBecomeMain: Bool { false }

    /// Places it over a rectangle given in global top-left coordinates.
    func cover(_ rect: CGRect) {
        setFrame(ScreenSpace.flip(rect, mainHeight: DisplayCatalog.mainHeight), display: false)
    }

    /// Shows it, fading in unless Reduce Motion is on.
    func appear(key: Bool = false) {
        let fade = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        alphaValue = fade ? 0 : 1
        if key { makeKeyAndOrderFront(nil) } else { orderFrontRegardless() }
        guard fade else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            animator().alphaValue = 1
        }
    }

    /// Hides it, fading out unless Reduce Motion is on.
    func disappear() {
        guard isVisible else { return }
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return orderOut(nil) }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                // Shown again while fading out: leave it.
                guard let self, self.alphaValue == 0 else { return }
                self.orderOut(nil)
            }
        })
    }
}

/// A short line of text on a Liquid Glass capsule: the grid's label and key hint, the drop
/// preview's size, "No window to place".
@MainActor
final class GlassLabel: NSView {
    private let glass = NSGlassEffectView()
    private let field = NSTextField(labelWithString: "")
    var maxWidth: CGFloat = 640

    init(font: NSFont = .systemFont(ofSize: 13, weight: .medium)) {
        super.init(frame: .zero)
        field.font = font
        field.lineBreakMode = .byTruncatingMiddle
        field.alignment = .center
        field.textColor = .labelColor
        glass.cornerRadius = 14
        // The text sits over the glass rather than inside it: the glass lays out its own
        // content view with insets of its own, which clipped the text.
        addSubview(glass)
        addSubview(field)
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError() }

    var text: String {
        get { field.stringValue }
        set { field.stringValue = newValue; needsLayout = true }
    }

    /// The size it wants: the text plus padding, no wider than `maxWidth`.
    var fittingSizeForText: CGSize {
        let text = (field.stringValue as NSString).size(withAttributes: [.font: field.font as Any])
        return CGSize(width: min(ceil(text.width) + 40, maxWidth), height: ceil(text.height) + 12)
    }

    /// Centers it on a point in its superview.
    func center(at point: CGPoint) {
        let size = fittingSizeForText
        frame = CGRect(x: (point.x - size.width / 2).rounded(), y: (point.y - size.height / 2).rounded(),
                       width: size.width, height: size.height)
        glass.frame = bounds
        field.frame = bounds.insetBy(dx: 16, dy: 6)
    }
}

/// A short message on a glass capsule in the middle of the display under the pointer, gone
/// after 1.5 s: "No window to place".
@MainActor
enum OverlayToast {
    private static var panel: OverlayPanel?
    private static var hide: DispatchWorkItem?

    static func show(_ text: String) {
        Diagnostics.note("toast: \(text)")
        let panel = self.panel ?? OverlayPanel(takesKeys: false, clickThrough: true)
        self.panel = panel
        let label = GlassLabel(font: .systemFont(ofSize: 15, weight: .medium))
        label.text = text
        let size = label.fittingSizeForText
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let screen else { return }
        let frame = CGRect(x: screen.frame.midX - size.width / 2, y: screen.frame.midY - size.height / 2,
                           width: size.width, height: size.height)
        panel.setFrame(frame, display: false)
        let view = NSView(frame: CGRect(origin: .zero, size: size))
        view.addSubview(label)
        label.center(at: CGPoint(x: size.width / 2, y: size.height / 2))
        panel.contentView = view
        panel.appear()
        NSAccessibility.post(element: panel, notification: .announcementRequested,
                             userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue])
        hide?.cancel()
        let work = DispatchWorkItem { MainActor.assumeIsolated { panel.disappear() } }
        hide = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }
}
