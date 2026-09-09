import Foundation
import Markdown

/// Renders a Markdown source string into a standalone HTML5 document.
///
/// The body fragment is produced by `swift-markdown`'s vendored `HTMLFormatter`,
/// then wrapped in a minimal HTML5 shell with embedded default styling.
public enum HTMLExporter {

    /// Render `markdown` into a complete HTML5 document titled `title`.
    ///
    /// - Parameters:
    ///   - markdown: CommonMark source.
    ///   - title: Plain-text title; HTML-escaped before injection.
    /// - Returns: A standalone HTML5 document string starting with `<!DOCTYPE html>`.
    public static func render(markdown: String, title: String) -> String {
        let body = HTMLFormatter.format(markHighlights(in: markdown))
        let escapedTitle = htmlEscape(title)

        return """
            <!DOCTYPE html>
            <html lang="en">
            <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <title>\(escapedTitle)</title>
            <style>\(defaultCSS)</style>
            </head>
            <body>
            <article>
            \(body)</article>
            </body>
            </html>
            """
    }

    /// `==text==` → `<mark>text</mark>`. cmark passes inline HTML through, so
    /// this pre-pass is enough. Fenced blocks are passed through untouched.
    /// ponytail: still rewrites inside inline code spans; switch to a
    /// post-AST rewrite if that ever matters.
    static func markHighlights(in markdown: String) -> String {
        var inFence = false
        // `components` (not `split`) so `\r\n` splits on the `\n` — Swift
        // treats CRLF as a single `Character`, which `split` would not break.
        return markdown.components(separatedBy: "\n").map { text -> String in
            let trimmed = text.drop { $0 == " " || $0 == "\t" }
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                inFence.toggle()
                return text
            }
            if inFence { return text }
            let units = Array(text.utf16)
            var rebuilt = ""
            var cursor = 0
            for span in HighlightScanner.scan(line: text) {
                rebuilt += String(decoding: units[cursor..<span.location], as: UTF16.self)
                rebuilt += "<mark>"
                rebuilt += String(
                    decoding: units[(span.location + 2)..<(span.location + span.length - 2)], as: UTF16.self)
                rebuilt += "</mark>"
                cursor = span.location + span.length
            }
            rebuilt += String(decoding: units[cursor...], as: UTF16.self)
            return rebuilt
        }.joined(separator: "\n")
    }

    // MARK: - Private

    private static func htmlEscape(_ string: String) -> String {
        var result = ""
        result.reserveCapacity(string.count)
        for character in string {
            switch character {
            case "&": result.append("&amp;")
            case "<": result.append("&lt;")
            case ">": result.append("&gt;")
            case "\"": result.append("&quot;")
            default: result.append(character)
            }
        }
        return result
    }

    private static let defaultCSS = """

        body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; max-width: 720px; margin: 2rem auto; padding: 0 1rem; line-height: 1.6; }
        code { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; background: rgba(127,127,127,.12); padding: .15em .35em; border-radius: 3px; }
        pre { background: rgba(127,127,127,.12); padding: 1rem; overflow-x: auto; border-radius: 6px; }
        pre code { background: transparent; padding: 0; border-radius: 0; }
        blockquote { border-left: 4px solid rgba(127,127,127,.3); padding-left: 1rem; margin-left: 0; }
        h1, h2, h3, h4, h5, h6 { line-height: 1.25; margin-top: 1.5rem; }
        img { max-width: 100%; height: auto; }
        mark { background: rgba(255,214,10,.35); padding: 0 .1em; border-radius: 2px; }

        """
}
