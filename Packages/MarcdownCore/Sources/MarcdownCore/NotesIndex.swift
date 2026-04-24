import Foundation

/// A lightweight summary of a note used by list UIs and quick switchers.
public struct NoteSummary: Hashable, Sendable, Identifiable {
    public let id: URL
    public var title: String
    public var modifiedAt: Date
    public var preview: String
    public var characterCount: Int

    public init(id: URL, title: String, modifiedAt: Date, preview: String, characterCount: Int) {
        self.id = id
        self.title = title
        self.modifiedAt = modifiedAt
        self.preview = preview
        self.characterCount = characterCount
    }
}

/// Serialized in-memory index of `.md` files in a single directory.
///
/// Watches the directory with `DispatchSourceFileSystemObject` — chosen over
/// `NSFilePresenter` because we already have clean `actor`/`Task` boundaries
/// and DispatchSource is mechanically simpler for one directory. Events are
/// dropped onto a background queue and hop into the actor via `Task`.
///
/// Consumers observe updates via `updates` — an `AsyncStream<[NoteSummary]>`.
public actor NotesIndex {
    public enum IndexError: Error, Sendable {
        case directoryUnavailable(URL)
        case createFailed(URL, underlying: String)
        case deleteFailed(URL, underlying: String)
        case renameFailed(URL, underlying: String)
    }

    private let directory: URL
    private let fileManager: FileManager

    private var cached: [NoteSummary] = []
    private var continuations: [UUID: AsyncStream<[NoteSummary]>.Continuation] = [:]
    private var watcher: DirectoryWatcher?

    public init(directory: URL = NoteLocation.defaultDirectory, fileManager: FileManager = .default) {
        self.directory = directory
        self.fileManager = fileManager
    }

    /// Ensures the directory exists, performs the first scan, and starts watching.
    public func start() async throws {
        try ensureDirectoryExists()
        cached = scanSync()
        startWatcher()
    }

    /// Stops watching — used by tests to release the dispatch source.
    public func stop() {
        watcher?.cancel()
        watcher = nil
        for continuation in continuations.values {
            continuation.finish()
        }
        continuations.removeAll()
    }

    deinit {
        watcher?.cancel()
        for continuation in continuations.values {
            continuation.finish()
        }
    }

    /// Current snapshot of the index. Safe to call from any isolation.
    public func snapshot() -> [NoteSummary] {
        cached
    }

    /// AsyncStream of snapshots. Emits the current snapshot on subscription and
    /// then every time the index refreshes.
    public func updates() -> AsyncStream<[NoteSummary]> {
        AsyncStream { continuation in
            let id = UUID()
            continuation.yield(cached)
            continuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { [weak self] in await self?.removeContinuation(id: id) }
            }
        }
    }

    private func removeContinuation(id: UUID) {
        continuations.removeValue(forKey: id)
    }

    /// Creates `Untitled N.md` where N is the smallest unused positive integer.
    @discardableResult
    public func create() async throws -> URL {
        try ensureDirectoryExists()

        let existing = Set(
            (try? fileManager.contentsOfDirectory(atPath: directory.path(percentEncoded: false))) ?? []
        )
        var n = 1
        while existing.contains("Untitled \(n).md") {
            n += 1
        }
        let url = directory.appendingPathComponent("Untitled \(n).md", isDirectory: false)
        do {
            try "".write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw IndexError.createFailed(url, underlying: String(describing: error))
        }
        refresh()
        return url
    }

    /// Moves the file at `url` to the Trash. Never permanent-deletes.
    public func delete(_ url: URL) async throws {
        do {
            var resulting: NSURL?
            try fileManager.trashItem(at: url, resultingItemURL: &resulting)
        } catch {
            throw IndexError.deleteFailed(url, underlying: String(describing: error))
        }
        refresh()
    }

    /// Duplicates the file at `url` with the given `body`, creating a new
    /// file named `copy-of-<originalStem>.md`.
    @discardableResult
    public func duplicate(url: URL, body: String) async throws -> URL {
        let originalStem = url.deletingPathExtension().lastPathComponent
        let slug = Self.slugify("copy-of-\(originalStem)")
        let target = try uniqueURL(forSlug: slug)
        do {
            try body.write(to: target, atomically: true, encoding: .utf8)
        } catch {
            throw IndexError.createFailed(target, underlying: String(describing: error))
        }
        refresh()
        return target
    }

    /// Renames the file to `newName.md` (slugified), handling collisions by
    /// appending `-2`, `-3`, etc. Returns the new URL.
    @discardableResult
    public func rename(_ url: URL, to newName: String) async throws -> URL {
        let slug = Self.slugify(newName)
        guard !slug.isEmpty else {
            throw IndexError.renameFailed(url, underlying: "empty slug")
        }
        let target = try uniqueURL(forSlug: slug, excluding: url)
        guard target != url else { return url }
        do {
            try fileManager.moveItem(at: url, to: target)
        } catch {
            throw IndexError.renameFailed(url, underlying: String(describing: error))
        }
        refresh()
        return target
    }

    /// Returns a URL for `<slug>.md`, or `<slug>-2.md`, `<slug>-3.md`, ... if
    /// the plain name is taken by a file other than `excluding`.
    public func uniqueURL(forSlug slug: String, excluding: URL? = nil) throws -> URL {
        let candidate = directory.appendingPathComponent("\(slug).md", isDirectory: false)
        if !fileExists(at: candidate) || candidate == excluding {
            return candidate
        }
        var n = 2
        while true {
            let alt = directory.appendingPathComponent("\(slug)-\(n).md", isDirectory: false)
            if !fileExists(at: alt) || alt == excluding {
                return alt
            }
            n += 1
        }
    }

    // MARK: - Internals

    private func ensureDirectoryExists() throws {
        if !fileManager.fileExists(atPath: directory.path(percentEncoded: false)) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    private func fileExists(at url: URL) -> Bool {
        fileManager.fileExists(atPath: url.path(percentEncoded: false))
    }

    /// Re-scans and broadcasts to continuations.
    private func refresh() {
        cached = scanSync()
        for continuation in continuations.values {
            continuation.yield(cached)
        }
    }

    private func scanSync() -> [NoteSummary] {
        guard
            let entries = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
        else {
            return []
        }

        var summaries: [NoteSummary] = []
        summaries.reserveCapacity(entries.count)
        for url in entries where url.pathExtension.lowercased() == "md" {
            let resourceValues = try? url.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey])
            if resourceValues?.isRegularFile != true { continue }
            let modifiedAt = resourceValues?.contentModificationDate ?? Date.distantPast

            let body = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            let title = Note.extractTitle(from: body) ?? url.deletingPathExtension().lastPathComponent
            let preview = Self.makePreview(from: body)
            let characterCount = body.count
            summaries.append(
                NoteSummary(id: url, title: title, modifiedAt: modifiedAt, preview: preview, characterCount: characterCount)
            )
        }
        summaries.sort { $0.modifiedAt > $1.modifiedAt }
        return summaries
    }

    private func startWatcher() {
        let watcher = DirectoryWatcher(url: directory)
        watcher.onChange = { [weak self] in
            Task { [weak self] in
                await self?.refresh()
            }
        }
        watcher.start()
        self.watcher = watcher
    }

    // MARK: - Helpers

    static func makePreview(from body: String, limit: Int = 120) -> String {
        var lines: [Substring] = []
        for raw in body.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = raw.drop(while: { $0 == " " || $0 == "\t" })
            if trimmed.hasPrefix("#") { continue } // skip any heading
            if trimmed.isEmpty { continue }
            lines.append(trimmed)
            if lines.joined(separator: " ").count >= limit { break }
        }
        let combined = lines.joined(separator: " ")
        if combined.count <= limit { return String(combined) }
        let cutoff = combined.index(combined.startIndex, offsetBy: limit)
        return String(combined[..<cutoff])
    }

    /// Converts a freeform title into a safe filename stem:
    /// lowercase, spaces collapsed to `-`, strip anything outside
    /// `a-z0-9-_`. Leading/trailing hyphens trimmed.
    public static func slugify(_ input: String) -> String {
        let lower = input.lowercased()
        var out = ""
        var lastWasHyphen = false
        for scalar in lower.unicodeScalars {
            let ch = Character(scalar)
            if ch.isLetter || ch.isNumber {
                out.append(ch)
                lastWasHyphen = false
            } else if ch == "_" {
                out.append(ch)
                lastWasHyphen = false
            } else {
                if !lastWasHyphen && !out.isEmpty {
                    out.append("-")
                    lastWasHyphen = true
                }
            }
        }
        while out.hasSuffix("-") { out.removeLast() }
        while out.hasPrefix("-") { out.removeFirst() }
        return out
    }
}

/// Minimal directory-change watcher. Not an actor — it owns a single
/// `DispatchSourceFileSystemObject` and forwards events to a callback.
///
/// The file descriptor, dispatch source, and `onChange` callback are all
/// accessed only from the owning actor (`NotesIndex`), so no additional
/// synchronization is required. We declare `@unchecked Sendable` only because
/// the dispatch machinery crosses threads internally and is safe by design.
private final class DirectoryWatcher: @unchecked Sendable {
    private let url: URL
    private var source: DispatchSourceFileSystemObject?
    private var descriptor: Int32 = -1
    var onChange: (@Sendable () -> Void)?

    init(url: URL) {
        self.url = url
    }

    func start() {
        let fd = open(url.path(percentEncoded: false), O_EVTONLY)
        guard fd >= 0 else { return }
        descriptor = fd
        let queue = DispatchQueue(label: "dev.marcdown.notesindex.watch", qos: .utility)
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .rename, .delete, .attrib],
            queue: queue
        )
        source.setEventHandler { [weak self] in
            self?.onChange?()
        }
        source.setCancelHandler { [fd] in
            close(fd)
        }
        source.resume()
        self.source = source
    }

    func cancel() {
        source?.cancel()
        source = nil
        descriptor = -1
    }

    deinit {
        source?.cancel()
    }
}
