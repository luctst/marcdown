import AppKit

extension NSView {
    /// Returns the first descendant (depth-first, including self) of the
    /// given type, or nil if none exists.
    func firstDescendant<T: NSView>(ofType type: T.Type) -> T? {
        if let me = self as? T { return me }
        for sub in subviews {
            if let found = sub.firstDescendant(ofType: type) { return found }
        }
        return nil
    }
}
