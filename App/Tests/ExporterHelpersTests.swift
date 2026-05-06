import Foundation
import MarcdownCore
import Testing
import UniformTypeIdentifiers

@testable import Marcdown

/// Pure helpers behind the Export sub-flow. These tests cover the parts of
/// `Exporter` that don't touch `NSSavePanel`: the format → metadata mapping
/// (extension/displayName/icon/utType) and the filename suggestion logic.
/// The rest of `Exporter` is exercised manually per the plan's QA matrix.
@MainActor
@Suite("ExportFormat mapping")
struct ExportFormatMappingTests {
    @Test("Markdown format uses the .md extension")
    func markdownFormatHasMdExtension() {
        #expect(ExportFormat.markdown.fileExtension == "md")
    }

    @Test("HTML format uses the .html extension")
    func htmlFormatHasHtmlExtension() {
        #expect(ExportFormat.html.fileExtension == "html")
    }

    @Test("PDF format uses the .pdf extension")
    func pdfFormatHasPdfExtension() {
        #expect(ExportFormat.pdf.fileExtension == "pdf")
    }

    @Test("Markdown display name is capitalized")
    func markdownDisplayNameIsCapitalized() {
        #expect(ExportFormat.markdown.displayName == "Markdown")
    }

    @Test("HTML display name is all caps")
    func htmlDisplayNameIsAllCaps() {
        #expect(ExportFormat.html.displayName == "HTML")
    }

    @Test("PDF display name is all caps")
    func pdfDisplayNameIsAllCaps() {
        #expect(ExportFormat.pdf.displayName == "PDF")
    }

    @Test("Every format has a non-empty SF Symbol icon name")
    func eachFormatHasNonEmptyIcon() {
        for format in ExportFormat.allCases {
            #expect(!format.icon.isEmpty, "ExportFormat.\(format) icon must not be empty")
        }
    }

    @Test("Markdown UTType is the canonical markdown identifier or a text-conforming fallback")
    func markdownUTTypeMatchesMarkdownIdentifier() {
        let format = ExportFormat.markdown
        #expect(
            format.utType.identifier == "net.daringfireball.markdown"
                || format.utType.conforms(to: .text)
        )
    }

    @Test("HTML UTType is UTType.html")
    func htmlUTTypeIsHTML() {
        #expect(ExportFormat.html.utType == UTType.html)
    }

    @Test("PDF UTType is UTType.pdf")
    func pdfUTTypeIsPDF() {
        #expect(ExportFormat.pdf.utType == UTType.pdf)
    }

    @Test("ExportFormat.allCases covers exactly the three shipping formats")
    func allFormatsAreCaseIterable() {
        // Regression guard: the format chooser renders three rows. Adding a new
        // format here without updating the chooser would silently break parity.
        #expect(ExportFormat.allCases.count == 3)
    }
}

@MainActor
@Suite("Exporter.suggestedName")
struct ExporterSuggestedNameTests {
    @Test("Extracts the title from the first heading")
    func extractsTitleFromFirstHeading() {
        let name = Exporter.suggestedName(text: "# My Note", fallbackURL: nil)
        #expect(name == "My Note")
    }

    @Test("Falls back to the filename (no extension) when no heading is present")
    func fallsBackToFilenameWhenNoTitle() {
        let url = URL(fileURLWithPath: "/tmp/scratch.md")
        let name = Exporter.suggestedName(text: "plain body, no heading", fallbackURL: url)
        #expect(name == "scratch")
    }

    @Test("Falls back to 'Untitled' when both text and URL are empty")
    func fallsBackToUntitledWhenAllNil() {
        let name = Exporter.suggestedName(text: "", fallbackURL: nil)
        #expect(name == "Untitled")
    }

    @Test("Prefers the extracted title over the fallback filename")
    func prefersTitleOverFilename() {
        let url = URL(fileURLWithPath: "/tmp/wrong.md")
        let name = Exporter.suggestedName(text: "# Real title\n", fallbackURL: url)
        #expect(name == "Real title")
    }

    @Test("Trims whitespace inside extracted titles")
    func trimsTitleWhitespace() {
        // Note.extractTitle is responsible for trimming; this test pins the
        // contract so a regression there surfaces in the export filename too.
        let name = Exporter.suggestedName(text: "#    Spaced out   ", fallbackURL: nil)
        #expect(name == "Spaced out")
    }
}
