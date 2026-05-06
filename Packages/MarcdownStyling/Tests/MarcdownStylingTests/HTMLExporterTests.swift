import Foundation
import MarcdownStyling
import Testing

@Suite("HTMLExporter")
struct HTMLExporterTests {

    @Test func renderProducesDoctypeAndShellElements() {
        let output = HTMLExporter.render(markdown: "Hello", title: "Doc")

        #expect(output.hasPrefix("<!DOCTYPE html>"))
        #expect(output.contains("<meta charset=\"UTF-8\">"))
        #expect(output.contains("<title>"))
        #expect(output.contains("</title>"))
    }

    @Test func headingMarkdownBecomesH1Element() {
        let output = HTMLExporter.render(markdown: "# Hi", title: "Doc")

        #expect(output.contains("<h1>Hi</h1>"))
    }

    @Test func strongMarkdownBecomesStrongElement() {
        let output = HTMLExporter.render(markdown: "**bold**", title: "Doc")

        #expect(output.contains("<strong>bold</strong>"))
    }

    @Test func emphasisMarkdownBecomesEmElement() {
        let output = HTMLExporter.render(markdown: "*italic*", title: "Doc")

        #expect(output.contains("<em>italic</em>"))
    }

    @Test func inlineCodeMarkdownBecomesCodeElement() {
        let output = HTMLExporter.render(markdown: "`code`", title: "Doc")

        #expect(output.contains("<code>code</code>"))
    }

    @Test func fencedCodeBlockBecomesPreWithCodeInside() {
        let source = """
            ```
            let x = 1
            ```
            """
        let output = HTMLExporter.render(markdown: source, title: "Doc")

        #expect(output.contains("<pre"))
        #expect(output.contains("<code"))
        // The <code> must live inside the <pre> block.
        if let preStart = output.range(of: "<pre"),
            let preEnd = output.range(of: "</pre>")
        {
            let preBlock = output[preStart.lowerBound..<preEnd.upperBound]
            #expect(preBlock.contains("<code"))
            #expect(preBlock.contains("let x = 1"))
        } else {
            Issue.record("Expected a <pre>...</pre> block in the output")
        }
    }

    @Test func titleIsHTMLEscapedToPreventInjection() {
        let malicious = "<script>alert(1)</script>"
        let output = HTMLExporter.render(markdown: "body", title: malicious)

        // Locate the <title>...</title> element and verify the raw script tag
        // is NOT present inside it.
        guard let openRange = output.range(of: "<title>"),
            let closeRange = output.range(of: "</title>", range: openRange.upperBound..<output.endIndex)
        else {
            Issue.record("Output did not contain a <title>...</title> element")
            return
        }
        let titleContent = output[openRange.upperBound..<closeRange.lowerBound]
        #expect(!titleContent.contains("<script>"))
        #expect(!titleContent.contains("</script>"))

        // The escaped form must appear somewhere — accept either named or
        // numeric character references.
        let hasNamedEscape = output.contains("&lt;script&gt;alert(1)&lt;/script&gt;")
        let hasNumericEscape =
            output.contains("&#60;script&#62;")
            || output.contains("&#x3c;script&#x3e;")
            || output.contains("&#x3C;script&#x3E;")
        #expect(hasNamedEscape || hasNumericEscape)
    }

    @Test func emptyMarkdownStillProducesValidShell() {
        let output = HTMLExporter.render(markdown: "", title: "Doc")

        #expect(output.contains("<!DOCTYPE html>"))
        #expect(output.contains("<html"))
        #expect(output.contains("</html>"))
    }

    @Test func outputContainsEmbeddedStyleElement() {
        let output = HTMLExporter.render(markdown: "Hello", title: "Doc")

        #expect(output.contains("<style"))
        #expect(output.contains("</style>"))
    }

    @Test func linkMarkdownBecomesAnchorElement() {
        let output = HTMLExporter.render(
            markdown: "[link](https://example.com)",
            title: "Doc"
        )

        #expect(output.contains("<a href=\"https://example.com\">link</a>"))
    }
}
