import Foundation
import Testing

@testable import MarcdownCore

@Suite("NoteSummary.characterCount")
struct NoteSummaryCharacterCountTests {
    private func makeTempDir() throws -> URL {
        let base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("marcdown-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    @Test("characterCount matches body length")
    func characterCountMatchesBody() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let body = "Hello, world!"
        let url = dir.appendingPathComponent("note.md")
        try body.write(to: url, atomically: true, encoding: .utf8)

        let index = NotesIndex(directory: dir)
        try await index.start()
        defer { Task { await index.stop() } }

        let snapshot = await index.snapshot()
        let entry = try #require(snapshot.first(where: { $0.id.lastPathComponent == "note.md" }))
        #expect(entry.characterCount == 13)
    }

    @Test("characterCount is zero for empty note")
    func characterCountEmpty() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let url = dir.appendingPathComponent("empty.md")
        try "".write(to: url, atomically: true, encoding: .utf8)

        let index = NotesIndex(directory: dir)
        try await index.start()
        defer { Task { await index.stop() } }

        let snapshot = await index.snapshot()
        let entry = try #require(snapshot.first(where: { $0.id.lastPathComponent == "empty.md" }))
        #expect(entry.characterCount == 0)
    }

    @Test("characterCount for multiline note includes all characters")
    func characterCountMultiline() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let body = "# Title\n\nBody text here."
        let url = dir.appendingPathComponent("multi.md")
        try body.write(to: url, atomically: true, encoding: .utf8)

        let index = NotesIndex(directory: dir)
        try await index.start()
        defer { Task { await index.stop() } }

        let snapshot = await index.snapshot()
        let entry = try #require(snapshot.first(where: { $0.id.lastPathComponent == "multi.md" }))
        #expect(entry.characterCount == body.count)
    }

    @Test("characterCount counts grapheme clusters for unicode")
    func characterCountUnicode() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let body = "Hello 🌍"
        let url = dir.appendingPathComponent("emoji.md")
        try body.write(to: url, atomically: true, encoding: .utf8)

        let index = NotesIndex(directory: dir)
        try await index.start()
        defer { Task { await index.stop() } }

        let snapshot = await index.snapshot()
        let entry = try #require(snapshot.first(where: { $0.id.lastPathComponent == "emoji.md" }))
        // Swift String.count uses grapheme clusters: "Hello 🌍" is 7 characters
        #expect(entry.characterCount == 7)
    }
}
