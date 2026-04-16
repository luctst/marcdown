import Foundation
import MarcdownCore
import Observation
import SwiftUI

/// View model that owns the in-memory note text, a debounced disk save, and
/// — for `Untitled N.md` files — an H1-driven auto-rename.
///
/// The debounce lives here rather than in the editor view so the View layer
/// stays declarative and the IO side-effect remains easy to reason about and
/// (later) test.
///
/// One `NoteViewModel` is bound to one URL; the owning `NotesStore` replaces
/// the instance (rather than mutating its URL) when the current note changes.
@MainActor
@Observable
final class NoteViewModel {
    var text: String = "" {
        didSet {
            guard text != oldValue, isLoaded else { return }
            scheduleSave()
        }
    }

    private(set) var url: URL
    private(set) var isLoaded: Bool = false
    private(set) var lastSaveError: String?

    /// Fired after a successful H1-driven rename so the `NotesStore` can
    /// update its `currentNote` URL.
    var onRename: (@MainActor (URL, URL) -> Void)?

    private let store: NoteStore
    private let index: NotesIndex?
    private let placeholder: String?
    private let debounceInterval: Duration

    /// Once true, the file was renamed away from `Untitled N.md` and we leave
    /// naming to the user from then on.
    private var hasBeenRenamed: Bool = false

    private var saveTask: Task<Void, Never>?

    init(
        url: URL,
        placeholder: String? = nil,
        store: NoteStore = NoteStore(),
        index: NotesIndex? = nil,
        debounceInterval: Duration = .milliseconds(300)
    ) {
        self.url = url
        self.placeholder = placeholder
        self.store = store
        self.index = index
        self.debounceInterval = debounceInterval
        self.hasBeenRenamed = !Self.isUntitled(url)

        Task { await self.load() }
    }

    private func load() async {
        do {
            let note: Note
            if let placeholder {
                note = try await store.loadOrCreate(at: url, placeholder: placeholder)
            } else {
                note = try await store.load(at: url)
            }
            self.text = note.body
            self.isLoaded = true
        } catch {
            self.lastSaveError = "Load failed: \(error)"
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        let snapshot = text
        let interval = debounceInterval
        saveTask = Task { [weak self] in
            do {
                try await Task.sleep(for: interval)
            } catch {
                return // cancelled
            }
            await self?.persist(snapshot)
        }
    }

    private func persist(_ body: String) async {
        do {
            _ = try await store.save(body: body, to: url)
            lastSaveError = nil
        } catch {
            lastSaveError = "Save failed: \(error)"
            return
        }
        // Rename is piggy-backed on the save debounce so we don't rename on
        // every keystroke.
        await maybeRename(for: body)
    }

    private func maybeRename(for body: String) async {
        guard !hasBeenRenamed, let index else { return }
        guard Self.isUntitled(url) else { return }
        guard let heading = Note.extractTitle(from: body) else { return }
        let slug = NotesIndex.slugify(heading)
        guard !slug.isEmpty else { return }

        do {
            let oldURL = url
            let newURL = try await index.rename(oldURL, to: slug)
            guard newURL != oldURL else { return }
            self.url = newURL
            self.hasBeenRenamed = true
            onRename?(oldURL, newURL)
        } catch {
            lastSaveError = "Rename failed: \(error)"
        }
    }

    private static func isUntitled(_ url: URL) -> Bool {
        let stem = url.deletingPathExtension().lastPathComponent
        return stem.range(of: #"^Untitled \d+$"#, options: .regularExpression) != nil
    }
}

