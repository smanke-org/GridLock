import Foundation
import GridLockKit
import IOKit
import Observation

/// Owns the desk library: a local file that is always the working copy, mirrored to this
/// Mac's own folder in iCloud Drive (the same scheme as WindowKeeper's profiles).
///
/// Each Mac writes only `iCloud Drive/GridLock/Macs/<hardware UUID>/desks.json`, so two
/// Macs never write the same file. With "Sync settings with your other Macs" on
/// (`isSharing`), it also reads the other Macs' files and folds in their newer grids,
/// palettes and custom layouts (`DeskSync`). iCloud I/O runs off the main thread: the first
/// access can raise a privacy prompt, and a call waiting on an unanswered prompt must not
/// freeze the menu.
@Observable
@MainActor
final class DeskStore {
    enum CloudState: Equatable {
        case unknown
        case synced(Date)
        /// iCloud Drive is off or signed out: desks are kept on this Mac only.
        case unavailable
        case failed(String)
    }

    private(set) var library: DeskLibrary
    private(set) var cloudState: CloudState = .unknown

    @ObservationIgnored let machineID: String
    @ObservationIgnored private var lastWritten: Data?
    @ObservationIgnored private var cloudWrite: DispatchWorkItem?
    /// The other Macs' libraries as last read, sharing or not: what a new desk is seeded from.
    @ObservationIgnored private(set) var others: [DeskLibrary] = []
    @ObservationIgnored private var pullTimer: Timer?

    /// Whether this Mac shares its grids, palettes and custom layouts and takes the other
    /// Macs' (settings sync is on). Recorded in the library, so other Macs know.
    var isSharing = false {
        didSet {
            guard isSharing != oldValue else { return }
            library.shares = isSharing
            persist()
            pullTimer?.invalidate()
            pullTimer = nil
            guard isSharing else { return }
            pullFromOtherMacs()
            pullTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.pullFromOtherMacs() }
            }
        }
    }
    private static let ioQueue = DispatchQueue(label: "GridLock.cloud", qos: .utility)

    /// `GRIDLOCK_DATA_DIR=<folder>` keeps a test run's desks in that folder and off iCloud,
    /// so tests never touch the real library (test copies otherwise share it).
    /// An agent CLI test copy (a Debug build run with `APP_STORE=<folder>`) keeps them in that folder.
    nonisolated static let testFolder: URL? = {
        let env = ProcessInfo.processInfo.environment
        #if DEBUG
        if AgentSocket.isTestRun, let store = env["APP_STORE"] { return URL(filePath: store, directoryHint: .isDirectory) }
        #endif
        return env["GRIDLOCK_DATA_DIR"].map { URL(filePath: $0, directoryHint: .isDirectory) }
    }()

    nonisolated static let localURL: URL = {
        if let testFolder { return testFolder.appending(path: "desks.json") }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appending(path: "GridLock/desks.json")
    }()

    /// iCloud Drive; for a test run, a folder in the test folder standing in for it, where a
    /// test puts other Macs' files.
    nonisolated static let cloudDriveURL = testFolder?.appending(path: "iCloud Drive", directoryHint: .isDirectory)
        ?? FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Mobile Documents/com~apple~CloudDocs", directoryHint: .isDirectory)

    nonisolated static let cloudRootURL = cloudDriveURL.appending(path: "GridLock/Macs", directoryHint: .isDirectory)

    nonisolated var cloudFolderURL: URL { Self.cloudRootURL.appending(path: machineID, directoryHint: .isDirectory) }

    init() {
        machineID = Self.hardwareUUID()
        let name = Host.current().localizedName ?? "This Mac"
        if let data = try? Data(contentsOf: Self.localURL),
           var loaded = try? Self.decoder.decode(DeskLibrary.self, from: data) {
            loaded.machineName = name
            loaded.machineID = machineID
            library = loaded
            lastWritten = data
        } else {
            library = DeskLibrary(machineID: machineID, machineName: name)
        }
    }

    /// After a reinstall, or with the local file deleted, this Mac's iCloud copy is adopted
    /// if nothing has been set up here yet.
    func recoverFromCloudIfEmpty(then completion: @escaping @MainActor () -> Void) {
        guard Self.testFolder == nil, library.desks.isEmpty, library.customLayouts.isEmpty else { return }
        let url = cloudFolderURL.appending(path: "desks.json")
        Self.ioQueue.async {
            let data = Self.coordinatedRead(url)
            Task { @MainActor in
                guard let data, let cloud = try? Self.decoder.decode(DeskLibrary.self, from: data),
                      !cloud.desks.isEmpty || !cloud.customLayouts.isEmpty,
                      self.library.desks.count <= 1, self.library.customLayouts.isEmpty
                else { return }
                Diagnostics.note("recovered \(cloud.desks.count) desk(s) from iCloud")
                self.library.desks = cloud.desks
                self.library.customLayouts = cloud.customLayouts
                self.persist()
                completion()
            }
        }
    }

    // MARK: - Editing

    func desk(id: UUID?) -> Desk? {
        guard let id else { return nil }
        return library.desks.first { $0.id == id }
    }

    func add(_ desk: Desk) {
        library.desks.append(desk)
        persist()
    }

    func update(_ desk: Desk) {
        guard let i = library.desks.firstIndex(where: { $0.id == desk.id }), library.desks[i] != desk else { return }
        library.desks[i] = desk
        persist()
    }

    /// Changes one display's settings at one desk, and nowhere else.
    func update(desk id: UUID, display key: String, _ change: (inout DisplaySettings) -> Void) {
        if library.updateSettings(desk: id, display: key, change) { persist() }
    }

    /// Paste Settings: another display's grid and palette.
    func paste(_ clip: DisplaySettings, desk id: UUID, display key: String) {
        update(desk: id, display: key) { $0 = $0.pasting(clip) }
    }

    /// Reset to Defaults: what GridLock suggests for the display's shape.
    func reset(desk id: UUID, display key: String) {
        let size = desk(id: id)?.displays.first { $0.key == key }?.bounds.cgRect.size ?? .zero
        update(desk: id, display: key) { $0 = .suggested(for: size) }
    }

    func rename(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, var desk = desk(id: id) else { return }
        desk.name = trimmed
        update(desk)
    }

    func delete(_ id: UUID) {
        library.desks.removeAll { $0.id == id }
        persist()
    }

    // MARK: - Other Macs

    /// Reads the other Macs' libraries and folds in what they share that's newer.
    func pullFromOtherMacs() {
        guard isSharing else { return }
        let root = Self.cloudRootURL, me = machineID
        Self.ioQueue.async {
            let folders = (try? FileManager.default.contentsOfDirectory(
                at: root, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles)) ?? []
            let libraries = folders.filter { $0.lastPathComponent != me }.compactMap { folder in
                Self.coordinatedRead(folder.appending(path: "desks.json")).flatMap { try? Self.decoder.decode(DeskLibrary.self, from: $0) }
            }
            Task { @MainActor in self.adopt(libraries) }
        }
    }

    private func adopt(_ libraries: [DeskLibrary]) {
        others = libraries
        guard isSharing else { return }
        let merged = DeskSync.merge(library, with: libraries)
        guard let before = try? Self.encoder.encode(library), let after = try? Self.encoder.encode(merged), before != after else { return }
        library = merged
        Diagnostics.note("sync: took newer grids, palettes or layouts from \(libraries.filter(\.shares).map(\.machineName).joined(separator: ", "))")
        persist()
    }

    func saveCustomLayout(_ layout: CustomLayout) {
        library.saveCustomLayout(layout)
        persist()
    }

    /// Also takes the layout out of every palette that showed it.
    func deleteCustomLayout(_ id: UUID) {
        library.removeCustomLayout(id)
        persist()
    }

    // MARK: - Saving

    private nonisolated static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private nonisolated static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    /// Writes only when something actually changed, so nothing is rewritten or re-synced
    /// for an edit that ends where it started.
    private func persist() {
        guard let data = try? Self.encoder.encode(library), data != lastWritten else { return }
        do {
            try FileManager.default.createDirectory(at: Self.localURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: Self.localURL, options: .atomic)
            lastWritten = data
        } catch {
            Diagnostics.note("could not write \(Self.localURL.path): \(error.localizedDescription)")
            return
        }
        scheduleCloudWrite(data)
    }

    /// Batched: a burst of edits (dragging a stepper) becomes one upload.
    private func scheduleCloudWrite(_ data: Data) {
        cloudWrite?.cancel()
        let folder = cloudFolderURL
        let work = DispatchWorkItem {
            Self.ioQueue.async {
                let result = Self.writeToCloud(data, folder: folder)
                Task { @MainActor in self.cloudState = result }
            }
        }
        cloudWrite = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
    }

    nonisolated private static func writeToCloud(_ data: Data, folder: URL) -> CloudState {
        guard FileManager.default.fileExists(atPath: cloudDriveURL.path) else { return .unavailable }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let file = folder.appending(path: "desks.json")
            var coordinationError: NSError?
            var writeError: Error?
            NSFileCoordinator().coordinate(writingItemAt: file, options: .forReplacing, error: &coordinationError) { url in
                do { try data.write(to: url, options: .atomic) } catch { writeError = error }
            }
            if let error = coordinationError ?? writeError { throw error }
            return .synced(Date())
        } catch {
            Diagnostics.note("iCloud write failed: \(error.localizedDescription)")
            return .failed(error.localizedDescription)
        }
    }

    /// Coordinated, so a file iCloud has evicted to save space is downloaded first.
    nonisolated private static func coordinatedRead(_ url: URL) -> Data? {
        var result: Data?
        var error: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &error) { url in
            result = try? Data(contentsOf: url)
        }
        return result
    }

    // MARK: - Identity

    /// The hardware UUID: stable for the life of the Mac, unique per Mac, and the same
    /// after a reinstall — which is what lets a reinstall find its iCloud copy.
    private static func hardwareUUID() -> String {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        defer { IOObjectRelease(service) }
        let value = IORegistryEntryCreateCFProperty(service, kIOPlatformUUIDKey as CFString, kCFAllocatorDefault, 0)
        return value?.takeRetainedValue() as? String ?? "unknown-mac"
    }
}
