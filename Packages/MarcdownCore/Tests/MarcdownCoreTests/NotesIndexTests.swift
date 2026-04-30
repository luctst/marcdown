import Foundation
import Testing
@testable import MarcdownCore

@Suite("NotesIndex")
struct NotesIndexTests {
    /// Makes a unique temp directory for a single test. Caller is responsible
    /// for stopping the index and removing the dir.
    private func makeTempDir() throws -> URL {
        let base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("marcdown-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    @Test("create() produces Untitled 1.md, then Untitled 2.md")
    func createNumbering() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let index = NotesIndex(directory: dir)
        try await index.start()
        defer { Task { await index.stop() } }

        let first = try await index.create()
        #expect(first.lastPathComponent == "Untitled 1.md")

        let second = try await index.create()
        #expect(second.lastPathComponent == "Untitled 2.md")
    }

    @Test("snapshot uses H1 as title when present")
    func titleFromH1() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let url = dir.appendingPathComponent("note.md")
        try "# Hello\n\nbody text".write(to: url, atomically: true, encoding: .utf8)

        let index = NotesIndex(directory: dir)
        try await index.start()
        defer { Task { await index.stop() } }

        let snapshot = await index.snapshot()
        let entry = snapshot.first(where: { $0.id.lastPathComponent == "note.md" })
        #expect(entry?.title == "Hello")
        #expect(entry?.preview == "body text")
    }

    @Test("delete moves file to trash and drops it from snapshot")
    func deleteMovesToTrash() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let url = dir.appendingPathComponent("delete-me.md")
        try "content".write(to: url, atomically: true, encoding: .utf8)

        let index = NotesIndex(directory: dir)
        try await index.start()
        defer { Task { await index.stop() } }

        #expect(await index.snapshot().contains(where: { $0.id.lastPathComponent == "delete-me.md" }))

        try await index.delete(url)

        #expect(!FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))
        #expect(!(await index.snapshot().contains(where: { $0.id.lastPathComponent == "delete-me.md" })))
    }

    @Test("rename with collision appends -2")
    func renameCollision() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let taken = dir.appendingPathComponent("foo.md")
        try "first".write(to: taken, atomically: true, encoding: .utf8)

        let source = dir.appendingPathComponent("Untitled 1.md")
        try "second".write(to: source, atomically: true, encoding: .utf8)

        let index = NotesIndex(directory: dir)
        try await index.start()
        defer { Task { await index.stop() } }

        let renamed = try await index.rename(source, to: "foo")
        #expect(renamed.lastPathComponent == "foo-2.md")
        #expect(FileManager.default.fileExists(atPath: renamed.path(percentEncoded: false)))
    }

    @Test("external writes are reflected in the updates stream", .timeLimit(.minutes(1)))
    func externalWriteUpdatesStream() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let index = NotesIndex(directory: dir)
        try await index.start()
        defer { Task { await index.stop() } }

        let stream = await index.updates()

        // Externally write a new file to simulate another editor.
        let newFile = dir.appendingPathComponent("external.md")
        Task.detached {
            // Tiny delay so the stream is definitely listening before the event fires.
            try? await Task.sleep(for: .milliseconds(50))
            try? "# External".write(to: newFile, atomically: true, encoding: .utf8)
        }

        // Read up to 2s worth of emissions, stop as soon as we see the new file.
        let deadline = Date().addingTimeInterval(2.0)
        var sawFile = false
        for await snapshot in stream {
            if snapshot.contains(where: { $0.id.lastPathComponent == "external.md" }) {
                sawFile = true
                break
            }
            if Date() > deadline { break }
        }
        #expect(sawFile)
    }

    @Test("calling start twice is a no-op and behavior is unchanged", .timeLimit(.minutes(1)))
    func doubleStartIsIdempotent() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        // Pre-seed a file so we can verify the initial scan ran.
        let preexisting = dir.appendingPathComponent("seed.md")
        try "# Seed".write(to: preexisting, atomically: true, encoding: .utf8)

        let index = NotesIndex(directory: dir)
        defer { Task { await index.stop() } }

        // Two sequential starts must both succeed without throwing.
        try await index.start()
        try await index.start()

        // Snapshot still reflects the initial scan after the second start.
        let snapshot = await index.snapshot()
        #expect(snapshot.contains(where: { $0.id.lastPathComponent == "seed.md" }))

        // The watcher is still wired up: a new external file shows up in updates().
        // If a second watcher had been installed, we'd have two dispatch sources
        // pointing at the same fd; this test catches catastrophic regressions
        // (no watcher at all, or start() throwing on the second call).
        let stream = await index.updates()
        let newFile = dir.appendingPathComponent("after-second-start.md")
        Task.detached {
            try? await Task.sleep(for: .milliseconds(50))
            try? "# Later".write(to: newFile, atomically: true, encoding: .utf8)
        }

        let deadline = Date().addingTimeInterval(2.0)
        var sawFile = false
        for await snapshot in stream {
            if snapshot.contains(where: { $0.id.lastPathComponent == "after-second-start.md" }) {
                sawFile = true
                break
            }
            if Date() > deadline { break }
        }
        #expect(sawFile)
    }

    @Test("concurrent starts share the same task and both succeed")
    func concurrentStartsShareTask() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let seed = dir.appendingPathComponent("seed.md")
        try "# Seed".write(to: seed, atomically: true, encoding: .utf8)

        let index = NotesIndex(directory: dir)
        defer { Task { await index.stop() } }

        // Two concurrent start() calls should both await the same underlying
        // task and complete without error.
        async let first: Void = index.start()
        async let second: Void = index.start()
        try await first
        try await second

        let snapshot = await index.snapshot()
        #expect(snapshot.contains(where: { $0.id.lastPathComponent == "seed.md" }))
    }

    @Test("start retries successfully after a failed first attempt")
    func startRetriesAfterFailure() async throws {
        // Set up a parent dir, then put a *file* where the index expects a
        // directory. createDirectory(withIntermediateDirectories: true) fails
        // when an intermediate path component is a regular file, so the first
        // start() will throw. After we remove the blocker, a second start()
        // must succeed — proving the cached failed task was cleared.
        let parent = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: parent) }

        let blocker = parent.appendingPathComponent("blocker")
        try Data().write(to: blocker)
        let indexDir = blocker.appendingPathComponent("notes", isDirectory: true)

        let index = NotesIndex(directory: indexDir)
        defer { Task { await index.stop() } }

        await #expect(throws: (any Error).self) {
            try await index.start()
        }

        // Clear the blocker so the directory can be created on the retry.
        try FileManager.default.removeItem(at: blocker)

        try await index.start()

        // Sanity-check the index is functional after the successful retry.
        let created = try await index.create()
        #expect(created.lastPathComponent == "Untitled 1.md")
    }
}
