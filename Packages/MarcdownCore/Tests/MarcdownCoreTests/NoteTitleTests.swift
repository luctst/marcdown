import Foundation
import Testing
@testable import MarcdownCore

@Suite("Note title parsing")
struct NoteTitleTests {
    private func makeNote(body: String, filename: String = "scratch.md") -> Note {
        Note(
            id: URL(fileURLWithPath: "/tmp/\(filename)"),
            body: body,
            modifiedAt: Date()
        )
    }

    @Test("Falls back to filename when body has no H1")
    func fallbackToFilename() {
        let note = makeNote(body: "no headings here\nstill nothing")
        #expect(note.title == "scratch")
    }

    @Test("Picks the first H1 heading")
    func picksFirstH1() {
        let body = """
        # First
        body
        # Second
        """
        #expect(makeNote(body: body).title == "First")
    }

    @Test("Ignores H2 and deeper headings")
    func ignoresDeeperHeadings() {
        let body = """
        ## Subheading
        ### Deeper
        # Real Title
        """
        #expect(makeNote(body: body).title == "Real Title")
    }

    @Test("Trims whitespace around the heading text")
    func trimsHeadingWhitespace() {
        let body = "#    Lots of space   \nbody"
        #expect(makeNote(body: body).title == "Lots of space")
    }

    @Test("Allows leading whitespace before the hash")
    func allowsLeadingWhitespace() {
        let body = "   # Indented Title\n"
        #expect(makeNote(body: body).title == "Indented Title")
    }

    @Test("Empty H1 falls back to filename")
    func emptyH1FallsBack() {
        let note = makeNote(body: "# \nbody", filename: "notes.md")
        #expect(note.title == "notes")
    }
}
