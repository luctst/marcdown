import Foundation

/// A markdown note backed by a file on disk.
///
/// `id` is the file URL — the canonical identity for a note in this app.
/// `title` is derived: first `# H1` in the body, falling back to the filename
/// without its extension. This keeps titles in lockstep with the document.
public struct Note: Hashable, Sendable, Identifiable {
    public let id: URL
    public var body: String
    public var modifiedAt: Date

    public init(id: URL, body: String, modifiedAt: Date) {
        self.id = id
        self.body = body
        self.modifiedAt = modifiedAt
    }

    /// First `# H1` heading in the body, or filename (sans extension) as fallback.
    /// We only consider `#` (single hash) so `## foo` is not mistaken for a title.
    public var title: String {
        Self.extractTitle(from: body) ?? id.deletingPathExtension().lastPathComponent
    }

    public static func extractTitle(from body: String) -> String? {
        // Walk lines until we find one matching: optional whitespace, "# ",
        // then the heading text. Stop at the first match.
        for rawLine in body.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.drop(while: { $0 == " " || $0 == "\t" })
            guard line.hasPrefix("# ") else {
                // A line that starts with "##" or more is not an H1.
                if line.hasPrefix("#") { continue }
                continue
            }
            let heading = line.dropFirst(2).trimmingCharacters(in: .whitespaces)
            if !heading.isEmpty { return heading }
        }
        return nil
    }
}
