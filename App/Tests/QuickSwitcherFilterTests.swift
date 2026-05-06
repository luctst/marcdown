import Foundation
import MarcdownCore
import Testing

@testable import Marcdown

@MainActor
@Suite("QuickSwitcher.filter")
struct QuickSwitcherFilterTests {
    /// Helper to build a `NoteSummary` with sensible defaults so each test only
    /// names the fields it actually exercises.
    private func makeNote(
        title: String,
        preview: String = "",
        modifiedAt: Date = Date(timeIntervalSince1970: 0),
        characterCount: Int = 0,
        path: String? = nil
    ) -> NoteSummary {
        let filename = path ?? title.lowercased().replacingOccurrences(of: " ", with: "-")
        return NoteSummary(
            id: URL(fileURLWithPath: "/tmp/\(filename).md"),
            title: title,
            modifiedAt: modifiedAt,
            preview: preview,
            characterCount: characterCount
        )
    }

    @Test("Empty query returns all notes with score 0, preserving input order")
    func emptyQueryPreservesInputOrder() {
        // Caller (NotesIndex) hands us notes already sorted modifiedAt-desc;
        // filter must not re-sort when the query is empty, otherwise stable
        // identity is broken between the index and the switcher view.
        let newer = makeNote(title: "Beta", modifiedAt: Date(timeIntervalSince1970: 200))
        let older = makeNote(title: "Alpha", modifiedAt: Date(timeIntervalSince1970: 100))
        let result = QuickSwitcher.filter(notes: [newer, older], query: "")
        #expect(result.map(\.note.title) == ["Beta", "Alpha"])
        #expect(result.allSatisfy { $0.score == 0 })
    }

    @Test("Whitespace-only query is treated as empty")
    func whitespaceQueryIsTreatedAsEmpty() {
        let notes = [makeNote(title: "Beta"), makeNote(title: "Alpha")]
        let result = QuickSwitcher.filter(notes: notes, query: "   ")
        #expect(result.map(\.note.title) == ["Beta", "Alpha"])
        #expect(result.allSatisfy { $0.score == 0 })
    }

    @Test("Exact title match scores 160 (100 + 40 + 20)")
    func exactTitleMatchScores160() {
        let note = makeNote(title: "Inbox")
        let result = QuickSwitcher.filter(notes: [note], query: "Inbox")
        #expect(result.count == 1)
        #expect(result[0].score == 160)
    }

    @Test("Title prefix match scores 60 (40 + 20)")
    func titlePrefixMatchScores60() {
        let note = makeNote(title: "Inbox Items")
        let result = QuickSwitcher.filter(notes: [note], query: "Inbox")
        #expect(result.count == 1)
        #expect(result[0].score == 60)
    }

    @Test("Title-substring-only match scores 20")
    func titleSubstringOnlyScores20() {
        let note = makeNote(title: "Daily Inbox Review")
        let result = QuickSwitcher.filter(notes: [note], query: "Inbox")
        #expect(result.count == 1)
        #expect(result[0].score == 20)
    }

    @Test("Preview-only match scores 5")
    func previewOnlyMatchScores5() {
        let note = makeNote(title: "Random Title", preview: "discusses inbox at length")
        let result = QuickSwitcher.filter(notes: [note], query: "inbox")
        #expect(result.count == 1)
        #expect(result[0].score == 5)
    }

    @Test("Title match outranks preview match")
    func titleMatchOutranksPreviewMatch() {
        let titleHit = makeNote(title: "Inbox Notes", preview: "")
        let previewHit = makeNote(title: "Other", preview: "talks about inbox")
        let result = QuickSwitcher.filter(notes: [previewHit, titleHit], query: "inbox")
        #expect(result.map(\.note.title) == ["Inbox Notes", "Other"])
    }

    @Test("Equal scores fall back to modifiedAt-desc")
    func equalScoresFallBackToRecency() {
        // Both are pure substring-only title hits → score 20 each.
        let older = makeNote(
            title: "Daily Inbox Review", modifiedAt: Date(timeIntervalSince1970: 100), path: "older")
        let newer = makeNote(
            title: "Weekly Inbox Digest", modifiedAt: Date(timeIntervalSince1970: 200), path: "newer")
        let result = QuickSwitcher.filter(notes: [older, newer], query: "Inbox")
        #expect(result.map(\.note.id.lastPathComponent) == ["newer.md", "older.md"])
    }

    @Test("Query whitespace is trimmed before matching")
    func queryWhitespaceIsTrimmed() {
        let note = makeNote(title: "Inbox")
        let result = QuickSwitcher.filter(notes: [note], query: "  Inbox  ")
        #expect(result.count == 1)
        #expect(result[0].score == 160)
    }

    @Test("Matching is case-insensitive on both title and preview")
    func caseInsensitiveMatching() {
        let titleHit = makeNote(title: "INBOX")
        let previewHit = makeNote(title: "Other", preview: "INBOX section")
        let result = QuickSwitcher.filter(notes: [titleHit, previewHit], query: "inbox")
        #expect(result.count == 2)
        // Title hit (160) beats preview hit (5), regardless of input order.
        #expect(result[0].note.title == "INBOX")
        #expect(result[1].note.title == "Other")
    }

    @Test("Notes with score 0 are dropped when the query is non-empty")
    func zeroScoredNotesDroppedWhenQueryNonEmpty() {
        let hit = makeNote(title: "Inbox")
        let miss = makeNote(title: "Archive", preview: "nothing relevant")
        let result = QuickSwitcher.filter(notes: [hit, miss], query: "inbox")
        #expect(result.count == 1)
        #expect(result[0].note.title == "Inbox")
    }
}

@MainActor
@Suite("QuickSwitcher.ScoredNote")
struct ScoredNoteEquatableTests {
    @Test("Two ScoredNote values compare equal when note and score match")
    func scoredNoteEquatable() {
        let url = URL(fileURLWithPath: "/tmp/a.md")
        let date = Date(timeIntervalSince1970: 1)
        let note = NoteSummary(id: url, title: "A", modifiedAt: date, preview: "", characterCount: 0)
        let lhs = QuickSwitcher.ScoredNote(note: note, score: 20)
        let rhs = QuickSwitcher.ScoredNote(note: note, score: 20)
        let differentScore = QuickSwitcher.ScoredNote(note: note, score: 21)
        #expect(lhs == rhs)
        #expect(lhs != differentScore)
    }
}
