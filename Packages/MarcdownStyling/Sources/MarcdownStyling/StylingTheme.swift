import AppKit

/// Visual theme for the markdown styler.
///
/// Colors are intentionally semantic (system label / accent / etc.) so light,
/// dark, and accessibility increased-contrast modes Just Work without any
/// branching at the call site.
@MainActor
public struct StylingTheme {
    public var body: NSColor
    public var dim: NSColor
    public var accent: NSColor
    public var codeBackground: NSColor
    public var codeBlockBackground: NSColor
    public var quoteBar: NSColor
    /// Background painted behind `==highlighted==` text.
    public var highlight: NSColor
    /// Horizontal rule drawn in place of `---`.
    public var rule: NSColor
    /// Multiplier applied to every line box. 1.2 is the Bear-like "airy" default.
    public var lineHeightMultiple: CGFloat

    public init(
        body: NSColor,
        dim: NSColor,
        accent: NSColor,
        codeBackground: NSColor,
        codeBlockBackground: NSColor,
        quoteBar: NSColor,
        highlight: NSColor = NSColor.systemYellow.withAlphaComponent(0.35),
        rule: NSColor = .separatorColor,
        lineHeightMultiple: CGFloat = 1.2
    ) {
        self.body = body
        self.dim = dim
        self.accent = accent
        self.codeBackground = codeBackground
        self.codeBlockBackground = codeBlockBackground
        self.quoteBar = quoteBar
        self.highlight = highlight
        self.rule = rule
        self.lineHeightMultiple = lineHeightMultiple
    }

    /// Default theme using AppKit semantic colors.
    ///
    /// `codeBlockBackground` is intentionally softer than `codeBackground`:
    /// the inline-code chip is a narrow run where 0.12 alpha reads as a
    /// gentle highlight, but a fenced block covers a much larger area and
    /// the same alpha would feel heavy. 0.10 keeps the rounded container
    /// visible without dominating the page.
    public static var system: StylingTheme {
        StylingTheme(
            body: .labelColor,
            dim: .secondaryLabelColor,
            accent: .controlAccentColor,
            codeBackground: NSColor(white: 0.5, alpha: 0.12),
            codeBlockBackground: NSColor(white: 0.5, alpha: 0.10),
            quoteBar: .tertiaryLabelColor
        )
    }
}
