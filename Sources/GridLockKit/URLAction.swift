import Foundation

/// What a `gridlock://` URL asks for. The app runs it on the frontmost window of another app.
///
/// `snap?zone=left-half` is the form for scripts and Shortcuts. ToolHUD names an action by
/// the URL's host alone (and adds `?source=toolhud`), so its snap buttons use
/// `snap-left-half`. Anything else opens Settings.
public enum URLAction: Equatable, Sendable {
    case grid
    case undo
    /// Open the palette for the frontmost window; a click on a zone snaps it.
    case palette
    /// A zone name, checked by the app against its named zones.
    case snap(zone: String?)
    case settings

    public init?(_ url: URL) {
        guard url.scheme?.lowercased() == "gridlock" else { return nil }
        let host = url.host?.lowercased() ?? ""
        switch host {
        case "grid": self = .grid
        case "undo": self = .undo
        case "palette": self = .palette
        case "snap":
            let zone = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "zone" }?.value
            self = .snap(zone: zone?.lowercased())
        case _ where host.hasPrefix("snap-"): self = .snap(zone: String(host.dropFirst("snap-".count)))
        default: self = .settings
        }
    }
}
