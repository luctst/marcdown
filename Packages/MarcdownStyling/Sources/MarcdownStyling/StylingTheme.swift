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
            codeBackground: .marcdownCodeBackground,
            quoteBar: .tertiaryLabelColor
        )
    }
}

extension NSColor {
    /// Adaptive code-block background that resolves to a GitHub-style
    /// contrast in both light and dark appearances. Light mode darkens the
    /// canvas by 10 %, dark mode lifts the canvas by 8 % — both are clearly
    /// visible without competing with body text.
    fileprivate static let marcdownCodeBackground: NSColor = NSColor(name: nil) { appearance in
        switch appearance.bestMatch(from: [.darkAqua, .aqua]) {
        case .darkAqua:
            return NSColor(white: 1.0, alpha: 0.08)
        default:
            return NSColor(white: 0.0, alpha: 0.10)
        }
    }
}
