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
}
