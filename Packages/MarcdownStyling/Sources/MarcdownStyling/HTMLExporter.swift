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
        let body = HTMLFormatter.format(markdown)
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

    """
}
