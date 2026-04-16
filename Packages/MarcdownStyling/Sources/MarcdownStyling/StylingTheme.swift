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
    public var quoteBar: NSColor

    public init(
        body: NSColor,
        dim: NSColor,
        accent: NSColor,
        codeBackground: NSColor,
        quoteBar: NSColor
    ) {
        self.body = body
        self.dim = dim
        self.accent = accent
        self.codeBackground = codeBackground
        self.quoteBar = quoteBar
    }

    /// Default theme using AppKit semantic colors.
    public static var system: StylingTheme {
        StylingTheme(
            body: .labelColor,
            dim: .secondaryLabelColor,
            accent: .controlAccentColor,
            codeBackground: NSColor(white: 0.5, alpha: 0.12),
            quoteBar: .tertiaryLabelColor
        )
    }
}
