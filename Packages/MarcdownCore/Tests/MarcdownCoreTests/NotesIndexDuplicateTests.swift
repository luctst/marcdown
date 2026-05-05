import Foundation
import Testing

@testable import MarcdownCore

@Suite("NotesIndex.duplicate")
struct NotesIndexDuplicateTests {
    private func makeTempDir() throws -> URL {
        let base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("marcdown-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    @Test("duplicate creates file with correct content")
    func duplicateCreatesFileWithContent() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let original = dir.appendingPathComponent("my-note.md")
        let body = "# Hello\n\nSome body text."
        try body.write(to: original, atomically: true, encoding: .utf8)

        let index = NotesIndex(directory: dir)
        try await index.start()
        defer { Task { await index.stop() } }

        let duplicated = try await index.duplicate(url: original, body: body)

        #expect(FileManager.default.fileExists(atPath: duplicated.path(percentEncoded: false)))
        let contents = try String(contentsOf: duplicated, encoding: .utf8)
        #expect(contents == body)
    }

    @Test("duplicate slug is prefixed with copy-of")
    func duplicateSlugPrefix() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let original = dir.appendingPathComponent("my-note.md")
        try "content".write(to: original, atomically: true, encoding: .utf8)

        let index = NotesIndex(directory: dir)
        try await index.start()
        defer { Task { await index.stop() } }

        let duplicated = try await index.duplicate(url: original, body: "content")

        #expect(duplicated.lastPathComponent.hasPrefix("copy-of-"))
        #expect(duplicated.lastPathComponent == "copy-of-my-note.md")
    }

    @Test("duplicate avoids collision when duplicating twice")
    func duplicateAvoidsCollision() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let original = dir.appendingPathComponent("my-note.md")
        try "content".write(to: original, atomically: true, encoding: .utf8)

        let index = NotesIndex(directory: dir)
        try await index.start()
        defer { Task { await index.stop() } }

        let first = try await index.duplicate(url: original, body: "content")
        let second = try await index.duplicate(url: original, body: "content")

        #expect(first != second)
        #expect(first.lastPathComponent == "copy-of-my-note.md")
        #expect(second.lastPathComponent == "copy-of-my-note-2.md")
        #expect(FileManager.default.fileExists(atPath: first.path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: second.path(percentEncoded: false)))
    }

    @Test("duplicate appears in next snapshot")
    func duplicateAppearsInSnapshot() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let original = dir.appendingPathComponent("note.md")
        try "body".write(to: original, atomically: true, encoding: .utf8)

        let index = NotesIndex(directory: dir)
        try await index.start()
        defer { Task { await index.stop() } }

        try await index.duplicate(url: original, body: "body")

        let snapshot = await index.snapshot()
        #expect(snapshot.count == 2)
        #expect(snapshot.contains(where: { $0.id.lastPathComponent == "note.md" }))
        #expect(snapshot.contains(where: { $0.id.lastPathComponent == "copy-of-note.md" }))
    }

    @Test("duplicate with empty body creates empty file")
    func duplicateWithEmptyBody() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let original = dir.appendingPathComponent("empty.md")
        try "".write(to: original, atomically: true, encoding: .utf8)

        let index = NotesIndex(directory: dir)
        try await index.start()
        defer { Task { await index.stop() } }

        let duplicated = try await index.duplicate(url: original, body: "")

        #expect(FileManager.default.fileExists(atPath: duplicated.path(percentEncoded: false)))
        let contents = try String(contentsOf: duplicated, encoding: .utf8)
        #expect(contents == "")
    }
}
