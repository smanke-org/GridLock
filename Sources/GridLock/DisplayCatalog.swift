import AppKit
import GridLockKit
import IOKit

/// The displays connected right now, each with a stable key. Same route as WindowKeeper.
///
/// macOS has no public way to get a display's alphanumeric serial for a screen. The route
/// used here: CoreDisplay's info dictionary for a display ID names its framebuffer in the
/// I/O Registry (`IODisplayLocation`), and that framebuffer's `DisplayAttributes` carry the
/// EDID serials. Verified on Apple silicon with macOS 27 — it is private, so any failure
/// falls back to the public vendor/model/serial numbers, which `DisplayKey` copes with.
@MainActor
enum DisplayCatalog {
    static func current() -> [LiveDisplay] {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return [] }
        let mainID = CGMainDisplayID()
        let mainHeight = CGDisplayBounds(mainID).height

        var displays: [LiveDisplay] = screens.compactMap { screen in
            guard let id = displayID(of: screen) else { return nil }
            let isBuiltin = CGDisplayIsBuiltin(id) != 0
            return LiveDisplay(
                key: key(for: id, isBuiltin: isBuiltin),
                name: screen.localizedName,
                isBuiltin: isBuiltin,
                isMain: id == mainID,
                bounds: CGDisplayBounds(id),
                visible: ScreenSpace.flip(screen.visibleFrame, mainHeight: mainHeight)
            )
        }
        let keys = DisplayKey.disambiguate(displays.map(\.key), xs: displays.map { Double($0.bounds.minX) })
        for i in displays.indices { displays[i].key = keys[i] }
        return displays
    }

    static func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    /// The NSScreen for a display, to put an overlay window on it.
    static func screen(for display: LiveDisplay) -> NSScreen? {
        NSScreen.screens.first { screen in
            guard let id = displayID(of: screen) else { return false }
            return CGDisplayBounds(id) == display.bounds
        }
    }

    /// The main display's height, for flipping between AppKit and Accessibility coordinates.
    static var mainHeight: CGFloat { CGDisplayBounds(CGMainDisplayID()).height }

    private static func key(for id: CGDirectDisplayID, isBuiltin: Bool) -> String {
        let uuid = CGDisplayCreateUUIDFromDisplayID(id).map { CFUUIDCreateString(nil, $0.takeRetainedValue()) as String } ?? "\(id)"
        return DisplayKey.make(.init(
            isBuiltin: isBuiltin,
            vendor: CGDisplayVendorNumber(id),
            model: CGDisplayModelNumber(id),
            numericSerial: CGDisplaySerialNumber(id),
            alphanumericSerial: alphanumericSerial(for: id),
            displayUUID: uuid
        ))
    }

    private typealias InfoFunction = @convention(c) (CGDirectDisplayID) -> Unmanaged<CFDictionary>?

    private static let createInfoDictionary: InfoFunction? = {
        guard let handle = dlopen("/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay", RTLD_LAZY),
              let symbol = dlsym(handle, "CoreDisplay_DisplayCreateInfoDictionary")
        else { return nil }
        return unsafeBitCast(symbol, to: InfoFunction.self)
    }()

    static func alphanumericSerial(for id: CGDirectDisplayID) -> String? {
        guard let createInfoDictionary,
              let info = createInfoDictionary(id)?.takeRetainedValue() as? [String: Any],
              let path = info["IODisplayLocation"] as? String
        else { return nil }
        let entry = IORegistryEntryFromPath(kIOMainPortDefault, path)
        guard entry != 0 else { return nil }
        defer { IOObjectRelease(entry) }
        let options = IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents)
        let attributes = IORegistryEntrySearchCFProperty(entry, kIOServicePlane, "DisplayAttributes" as CFString, nil, options) as? [String: Any]
        let product = attributes?["ProductAttributes"] as? [String: Any]
        return product?["AlphanumericSerialNumber"] as? String
    }
}
