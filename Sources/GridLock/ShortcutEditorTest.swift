#if DEBUG
import AppKit
import Carbon.HIToolbox

/// `GRIDLOCK_EDITOR_TEST=<folder>` on an agent test copy (APP_STORE): opens Settings ›
/// Shortcuts and runs the shortcut editor on the test copy's own settings: "+" becomes ⇧ =,
/// a bare letter is refused, an F-key may stand alone, pressing Undo Move's keys moves them to
/// Show Grid, Esc cancels, Clear clears. Writes results.txt and pictures of the editor to the
/// folder, then quits.
@MainActor
enum ShortcutEditorTest {
    static func run(folder: String) async {
        let settings = AppSettings.shared
        settings.setShortcut("grid", ShortcutCatalog.item("grid")?.defaultKey)
        settings.setShortcut("undo", ShortcutCatalog.item("undo")?.defaultKey)
        SettingsWindow.shared.show(tab: "Shortcuts")
        try? await Task.sleep(for: .milliseconds(800))
        var out: [String] = []
        func recorders(in view: NSView) -> [ShortcutRecorder.RecorderButton] {
            ((view as? ShortcutRecorder.RecorderButton).map { [$0] } ?? []) + view.subviews.flatMap(recorders)
        }
        func shot(_ name: String, _ button: ShortcutRecorder.RecorderButton) {
            guard let view = button.debugPopoverView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
                out.append("no picture \(name)"); return
            }
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(filePath: folder + "/\(name).png"))
        }
        func press(_ model: ShortcutEditorModel, _ code: Int, _ flags: NSEvent.ModifierFlags) -> Bool {
            guard let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                                               windowNumber: 0, context: nil, characters: "",
                                               charactersIgnoringModifiers: "", isARepeat: false, keyCode: UInt16(code)) else { return false }
            return model.handle(event)
        }
        func finish() {
            try? (out.joined(separator: "\n") + "\n").write(toFile: folder + "/results.txt", atomically: true, encoding: .utf8)
            Diagnostics.note("editor test: " + out.joined(separator: "; "))
            exit(0)
        }
        guard let content = SettingsWindow.shared.debugWindow?.contentView,
              let grid = recorders(in: content).first(where: { $0.shortcutID == "grid" }) else {
            out.append("no Show Grid shortcut box in Settings"); return finish()
        }
        out.append("box before: \(grid.debugTitle)")
        grid.performClick(nil)
        try? await Task.sleep(for: .milliseconds(400))
        guard let model = grid.debugModel else { out.append("editor did not open"); return finish() }
        out.append("box while open: \(grid.debugTitle)")
        model.control = false; model.option = false; model.shift = false; model.command = false
        model.typed("+")
        out.append("plus: key \(model.keyText) shift \(model.shift) combo \(model.combo?.display ?? "-") problem \(model.problem ?? "-")")
        model.control = true; model.option = true
        out.append("plus with ⌃⌥: combo \(model.combo?.display ?? "-") problem \(model.problem ?? "-")")
        try? await Task.sleep(for: .milliseconds(200))
        shot("editor-plus", grid)
        model.control = false; model.option = false; model.shift = false; model.command = false
        model.typed("k")
        out.append("bare k: combo \(model.combo?.display ?? "-") problem \(model.problem ?? "-")")
        model.choose(kVK_F6)
        out.append("F6 alone: combo \(model.combo?.display ?? "-") problem \(model.problem ?? "-")")
        _ = press(model, kVK_ANSI_Z, [.control, .option])
        out.append("pressed ⌃⌥Z: combo \(model.combo?.display ?? "-") moves from \(model.movesFrom) problem \(model.problem ?? "-")")
        try? await Task.sleep(for: .milliseconds(200))
        shot("editor-moves", grid)
        model.finish?(.set(model.combo))
        try? await Task.sleep(for: .milliseconds(300))
        out.append("after Set: Show Grid \(settings.shortcut("grid")?.display ?? "none"), Undo Move \(settings.shortcut("undo")?.display ?? "none"), box \(grid.debugTitle), open \(grid.debugModel != nil)")

        grid.performClick(nil)
        try? await Task.sleep(for: .milliseconds(400))
        if let model = grid.debugModel {
            model.choose(kVK_ANSI_Q)
            _ = press(model, kVK_Escape, [])
            try? await Task.sleep(for: .milliseconds(300))
            out.append("after Esc: Show Grid \(settings.shortcut("grid")?.display ?? "none"), open \(grid.debugModel != nil)")
        }
        grid.performClick(nil)
        try? await Task.sleep(for: .milliseconds(400))
        if let model = grid.debugModel {
            model.finish?(.set(nil))
            try? await Task.sleep(for: .milliseconds(300))
            out.append("after Clear: Show Grid \(settings.shortcut("grid")?.display ?? "none"), box \(grid.debugTitle)")
        }
        // Put the test copy's settings back.
        settings.setShortcut("grid", ShortcutCatalog.item("grid")?.defaultKey)
        settings.setShortcut("undo", ShortcutCatalog.item("undo")?.defaultKey)
        finish()
    }
}
#endif
