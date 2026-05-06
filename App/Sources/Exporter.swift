import AppKit
import MarcdownCore
import MarcdownStyling
import UniformTypeIdentifiers

/// User-selectable export targets for the current note.
///
/// Each case carries the metadata the chooser UI and `Exporter` need: a
/// filename extension, a human-readable label, an SF Symbol for the row icon,
/// and a `UTType` for the save panel's content-type filter.
enum ExportFormat: String, CaseIterable, Identifiable, Sendable {
    case markdown
    case html
    case pdf

    var id: String { rawValue }

    var fileExtension: String {
        switch self {
        case .markdown: return "md"
        case .html: return "html"
        case .pdf: return "pdf"
        }
    }

    var displayName: String {
        switch self {
        case .markdown: return "Markdown"
        case .html: return "HTML"
        case .pdf: return "PDF"
        }
    }

    var icon: String {
        switch self {
        case .markdown: return "doc.plaintext"
        case .html: return "chevron.left.forwardslash.chevron.right"
        case .pdf: return "doc.richtext"
        }
    }

    var utType: UTType {
        switch self {
        case .markdown:
            // Prefer the canonical Daring Fireball identifier when registered;
            // fall back to a filename-extension lookup, then plain text so the
            // save panel always has *something* text-conforming to filter on.
            return UTType("net.daringfireball.markdown")
                ?? UTType(filenameExtension: "md")
                ?? .plainText
        case .html: return .html
        case .pdf: return .pdf
        }
    }
}

/// Drives the export sub-flow: filename suggestion, save panel, and writing
/// the chosen format to disk. The PDF path renders the same attributed string
/// the editor uses on screen so on-screen and exported styling stay in sync.
@MainActor
enum Exporter {

    /// Best-effort default name for the save panel.
    ///
    /// Order: extracted H1 title → fallback filename (sans extension) →
    /// `"Untitled"`. The returned value is the *base* name; the caller appends
    /// the format extension.
    static func suggestedName(text: String, fallbackURL: URL?) -> String {
        if let title = Note.extractTitle(from: text), !title.isEmpty {
            return title
        }
        if let url = fallbackURL {
            return url.deletingPathExtension().lastPathComponent
        }
        return "Untitled"
    }

    /// Show a save panel for `format` and write `text` to the chosen URL.
    ///
    /// - Returns: The URL written to, or `nil` if the user cancelled the panel.
    /// - Throws: Any IO or rendering error from the underlying writer.
    static func export(
        format: ExportFormat,
        text: String,
        suggestedName: String
    ) async throws -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(suggestedName).\(format.fileExtension)"
        panel.allowedContentTypes = [format.utType]
        panel.canCreateDirectories = true
        panel.directoryURL = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first
        panel.isExtensionHidden = false

        guard panel.runModal() == .OK, let url = panel.url else {
            return nil
        }

        switch format {
        case .markdown:
            try text.write(to: url, atomically: true, encoding: .utf8)
        case .html:
            let html = HTMLExporter.render(markdown: text, title: suggestedName)
            try html.write(to: url, atomically: true, encoding: .utf8)
        case .pdf:
            try writePDF(text: text, title: suggestedName, to: url)
        }

        return url
    }

    // MARK: - PDF

    /// Renders `text` through the editor's styler and prints it to a PDF at `url`.
    ///
    /// We reuse `MarkdownStyler` so the on-screen styling and the exported PDF
    /// share a single source of truth — adding a new style attribute in the
    /// editor immediately propagates to PDF exports without any extra work.
    private static func writePDF(text: String, title: String, to url: URL) throws {
        let styler = MarkdownStyler()
        let attributed = styler.attributedString(for: text)

        // Letter (8.5"×11") at 72 dpi, minus 1" margins on each side.
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 468, height: 648))
        textView.textStorage?.setAttributedString(attributed)
        if let container = textView.textContainer {
            textView.layoutManager?.ensureLayout(for: container)
        }

        let info = NSPrintInfo()
        info.paperSize = NSSize(width: 612, height: 792)
        info.topMargin = 72
        info.bottomMargin = 72
        info.leftMargin = 72
        info.rightMargin = 72
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url as NSURL

        let operation = NSPrintOperation(view: textView, printInfo: info)
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false

        if !operation.run() {
            throw CocoaError(.fileWriteUnknown)
        }
    }
}

/// Maps low-level errors into short, user-facing reasons for the export toast.
///
/// Cocoa file-write errors surface specific causes (out of space, permission
/// denied, conflict) so the toast can be actionable. Anything else falls back
/// to `localizedDescription` lowercased so it reads naturally inline.
extension Error {
    var userFacingReason: String {
        let cocoa = self as NSError
        if cocoa.domain == NSCocoaErrorDomain {
            switch cocoa.code {
            case NSFileWriteOutOfSpaceError: return "the disk is full"
            case NSFileWriteNoPermissionError: return "macOS denied write permission"
            case NSFileWriteFileExistsError: return "a file already exists at that path"
            default: break
            }
        }
        return localizedDescription.lowercased()
    }
}
