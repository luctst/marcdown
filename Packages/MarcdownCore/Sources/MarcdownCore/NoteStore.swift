import Foundation

/// Loads and saves a single note URL.
///
/// **Concurrency choice:** modeled as an `actor` rather than `@MainActor` because
/// disk IO has no business hopping to the main thread. Callers (the editor's
/// debounce timer, the app launch path) await results from any context. When
/// future slices add a folder index, watching, or batched IO, the actor is the
/// natural seam to keep everything serialized per-store.
public actor NoteStore {
    public enum StoreError: Error, Sendable {
        case fileMissing(URL)
        case readFailed(URL, underlying: String)
        case writeFailed(URL, underlying: String)
    }

    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    /// Ensures the directory exists, creating it if needed.
    public func ensureDirectoryExists(at directory: URL) throws {
        if !fileManager.fileExists(atPath: directory.path(percentEncoded: false)) {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }
    }

    /// Loads a note from `url`, creating it with `placeholder` if it does not exist.
    public func loadOrCreate(at url: URL, placeholder: String) throws -> Note {
        try ensureDirectoryExists(at: url.deletingLastPathComponent())

        if !fileManager.fileExists(atPath: url.path(percentEncoded: false)) {
            do {
                try placeholder.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                throw StoreError.writeFailed(url, underlying: String(describing: error))
            }
        }
        return try load(at: url)
    }

    public func load(at url: URL) throws -> Note {
        guard fileManager.fileExists(atPath: url.path(percentEncoded: false)) else {
            throw StoreError.fileMissing(url)
        }
        do {
            let body = try String(contentsOf: url, encoding: .utf8)
            let attrs = try fileManager.attributesOfItem(atPath: url.path(percentEncoded: false))
            let modified = (attrs[.modificationDate] as? Date) ?? Date()
            return Note(id: url, body: body, modifiedAt: modified)
        } catch let error as StoreError {
            throw error
        } catch {
            throw StoreError.readFailed(url, underlying: String(describing: error))
        }
    }

    /// Atomically writes `body` to `url`. Returns the new modification date.
    @discardableResult
    public func save(body: String, to url: URL) throws -> Date {
        do {
            try ensureDirectoryExists(at: url.deletingLastPathComponent())
            try body.write(to: url, atomically: true, encoding: .utf8)
            let attrs = try fileManager.attributesOfItem(atPath: url.path(percentEncoded: false))
            return (attrs[.modificationDate] as? Date) ?? Date()
        } catch {
            throw StoreError.writeFailed(url, underlying: String(describing: error))
        }
    }
}
