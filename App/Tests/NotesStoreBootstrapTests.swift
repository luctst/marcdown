import Foundation
import MarcdownCore
import Testing

@testable import Marcdown

/// Locks down the `isBootstrapping` contract that drives `QuickSwitcher`'s
/// loading state. Without this flag the switcher renders "No matching notes"
/// during the cold-open gap before `bootstrap()` resolves — a false empty
/// state visible on every fresh panel show. If the flag does not flip
/// `true → false` exactly when bootstrap finishes, that bug regresses
/// silently in the UI; this suite is the unit-level tripwire.
//
// Note: we don't verify the scratch-seed write itself because
// `NoteLocation.scratchNote` is hardcoded to `~/marcdown/scratch.md` and
// ignores the injected NotesIndex directory. Verifying the seed would
// require touching the user's home dir or refactoring NoteLocation/NotesStore
// for full DI — tracked separately. The flag transition through the
// empty-vault path is still covered by `isBootstrappingFalseAfterBootstrap`.
@MainActor
@Suite("NotesStore.isBootstrapping")
struct NotesStoreBootstrapTests {
    /// Builds a `NotesStore` wired to a freshly-created temp notes directory and
    /// an isolated `UserDefaults` suite, so tests never read from or write to
    /// the user's real `~/marcdown/` folder or shared defaults.
    private func makeStore() throws -> (store: NotesStore, cleanup: () -> Void) {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("marcdown-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let suiteName = "dev.marcdown.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard

        let store = NotesStore(index: NotesIndex(directory: dir), defaults: defaults)
        let cleanup: () -> Void = {
            try? FileManager.default.removeItem(at: dir)
            defaults.removePersistentDomain(forName: suiteName)
        }
        return (store, cleanup)
    }

    @Test("isBootstrapping is true synchronously after init, before bootstrap is called")
    func isBootstrappingTrueAfterInit() throws {
        let (store, cleanup) = try makeStore()
        defer { cleanup() }

        #expect(store.isBootstrapping == true)
    }

    @Test("isBootstrapping flips to false once bootstrap() resolves")
    func isBootstrappingFalseAfterBootstrap() async throws {
        let (store, cleanup) = try makeStore()
        defer { cleanup() }

        await store.bootstrap()

        #expect(store.isBootstrapping == false)
    }

    @Test("Calling bootstrap() a second time leaves isBootstrapping false")
    func isBootstrappingStaysFalseOnSecondBootstrap() async throws {
        // Idempotency guard: NotesStore is a long-lived singleton and bootstrap()
        // can be invoked again from app lifecycle paths. The flag must not
        // transiently flip back to true and re-trigger the loading state.
        let (store, cleanup) = try makeStore()
        defer { cleanup() }

        await store.bootstrap()
        #expect(store.isBootstrapping == false)

        await store.bootstrap()
        #expect(store.isBootstrapping == false)
    }
}
