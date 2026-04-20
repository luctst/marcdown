import Foundation
import MarcdownCore
import Observation
import SwiftUI

/// Main-actor, observable facade over `NotesIndex` for the UI.
///
/// Owns:
///  - the user's current note URL
///  - the list of all notes (mirrored from the index)
///  - a cap-9 "recently opened" list persisted to UserDefaults
@MainActor
@Observable
final class NotesStore {
    private(set) var notes: [NoteSummary] = []
    private(set) var recentlyOpened: [URL] = []
    private(set) var currentNote: URL?

    /// Published editor view model for the `currentNote`. Swapped out whenever
    /// the current note changes.
    private(set) var editor: NoteViewModel?

    private let index: NotesIndex
    private let defaults: UserDefaults
    private let defaultsKey = "dev.marcdown.recentlyOpened"
    private static let recentCap = 9

    private var streamTask: Task<Void, Never>?
    private var hasBootstrapped = false

    init(index: NotesIndex = NotesIndex(), defaults: UserDefaults = .standard) {
        self.index = index
        self.defaults = defaults
        self.recentlyOpened = Self.loadRecents(from: defaults, key: defaultsKey)
    }

    func bootstrap() async {
        guard !hasBootstrapped else { return }
        hasBootstrapped = true

        do {
            try await index.start()
        } catch {
            // If the directory can't be created we have nothing to show; the
            // empty-state path still produces a valid (empty) notes list.
        }

        let initialSnapshot = await index.snapshot()
        await apply(snapshot: initialSnapshot, ensureScratchIfEmpty: true)

        // Subscribe to live updates.
        let stream = await index.updates()
        streamTask?.cancel()
        streamTask = Task { [weak self] in
            for await snapshot in stream {
                await self?.apply(snapshot: snapshot, ensureScratchIfEmpty: false)
            }
        }
    }

    // No deinit cleanup needed: the streaming task captures `[weak self]`,
    // so it stops naturally once this store is released. Cross-actor cleanup
    // from a `deinit` is not allowed under Swift 6 strict concurrency anyway.


    private func apply(snapshot: [NoteSummary], ensureScratchIfEmpty: Bool) async {
        // Empty-state: on first boot, seed a scratch note.
        if snapshot.isEmpty && ensureScratchIfEmpty {
            let store = NoteStore()
            _ = try? await store.loadOrCreate(
                at: NoteLocation.scratchNote,
                placeholder: NoteLocation.scratchPlaceholder
            )
            let refreshed = await index.snapshot()
            await MainActor.run {
                self.notes = refreshed
                self.pruneRecents()
                if self.currentNote == nil, let first = refreshed.first {
                    self.open(first.id)
                }
            }
            return
        }

        self.notes = snapshot
        pruneRecents()

        if currentNote == nil, let first = snapshot.first {
            open(first.id)
        } else if let current = currentNote,
                  !snapshot.contains(where: { $0.id == current }) {
            // The current note was deleted externally; fall back.
            let next = nextFallback(excluding: current)
            if let next {
                open(next)
            } else {
                currentNote = nil
                editor = nil
            }
        }
    }

    // MARK: - Public API

    func open(_ url: URL) {
        currentNote = url
        pushRecent(url)
        editor = makeEditor(for: url)
    }

    func newNote() async {
        do {
            let url = try await index.create()
            open(url)
        } catch {
            // Swallow: the visible effect is no new note appears.
        }
    }

    func deleteCurrent() async {
        guard let current = currentNote else { return }
        let fallback = nextFallback(excluding: current)
        do {
            try await index.delete(current)
        } catch {
            return
        }
        recentlyOpened.removeAll { $0 == current }
        persistRecents()
        if let fallback {
            open(fallback)
        } else {
            currentNote = nil
            editor = nil
        }
    }

    func duplicateCurrent() async {
        guard let current = currentNote, let body = editor?.text else { return }
        do {
            let newURL = try await index.duplicate(url: current, body: body)
            open(newURL)
        } catch {
            // Swallow: same pattern as newNote()
        }
    }

    /// 1-based: ⌘1 → most recent, ⌘9 → oldest recent.
    func jumpToRecent(_ oneBasedIndex: Int) {
        let zeroBased = oneBasedIndex - 1
        guard recentlyOpened.indices.contains(zeroBased) else { return }
        open(recentlyOpened[zeroBased])
    }

    func prev() {
        guard let current = currentNote,
              let idx = notes.firstIndex(where: { $0.id == current }),
              !notes.isEmpty else { return }
        let newIdx = (idx - 1 + notes.count) % notes.count
        open(notes[newIdx].id)
    }

    func next() {
        guard let current = currentNote,
              let idx = notes.firstIndex(where: { $0.id == current }),
              !notes.isEmpty else { return }
        let newIdx = (idx + 1) % notes.count
        open(notes[newIdx].id)
    }

    // MARK: - Internals

    private func makeEditor(for url: URL) -> NoteViewModel {
        let vm = NoteViewModel(
            url: url,
            placeholder: nil,
            index: index
        )
        vm.onRename = { [weak self] oldURL, newURL in
            guard let self else { return }
            if self.currentNote == oldURL {
                self.currentNote = newURL
            }
            if let recentIdx = self.recentlyOpened.firstIndex(of: oldURL) {
                self.recentlyOpened[recentIdx] = newURL
                self.persistRecents()
            }
        }
        return vm
    }

    private func nextFallback(excluding url: URL) -> URL? {
        if let fromRecent = recentlyOpened.first(where: { $0 != url }) {
            return fromRecent
        }
        return notes.first(where: { $0.id != url })?.id
    }

    private func pushRecent(_ url: URL) {
        recentlyOpened.removeAll { $0 == url }
        recentlyOpened.insert(url, at: 0)
        if recentlyOpened.count > Self.recentCap {
            recentlyOpened.removeLast(recentlyOpened.count - Self.recentCap)
        }
        persistRecents()
    }

    private func pruneRecents() {
        let valid = Set(notes.map(\.id))
        let pruned = recentlyOpened.filter { valid.contains($0) }
        if pruned != recentlyOpened {
            recentlyOpened = pruned
            persistRecents()
        }
    }

    private func persistRecents() {
        defaults.set(recentlyOpened.map(\.absoluteString), forKey: defaultsKey)
    }

    private static func loadRecents(from defaults: UserDefaults, key: String) -> [URL] {
        let strings = defaults.stringArray(forKey: key) ?? []
        return strings.compactMap { URL(string: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) }
    }
}
