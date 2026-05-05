import AppKit
import SwiftUI

// MARK: - Model

/// Centralised state for Raycast-style tooltips. A single instance lives at
/// the panel root and is consumed by `.raycastTooltip` modifiers via the
/// SwiftUI environment.
///
/// Sibling-fluidity rule: once any tooltip is visible, subsequent show
/// requests skip the 400ms hover delay until everything is hidden again.
///
/// Rendering: tooltips render in a dedicated borderless `NSWindow` owned by
/// `TooltipWindowController` so they can escape the panel's content bounds.
@MainActor
@Observable
final class TooltipModel {
    struct Tip: Equatable {
        let id: UUID
        let label: String
        let shortcut: [String]
        let anchor: CGRect  // button frame in the panel coordinate space
    }

    /// The tooltip currently rendered, if any.
    private(set) var visible: Tip?

    /// The id of the most recent show request, used to ignore stale delays.
    private var pending: UUID?

    /// Cancellable delay task for the 400ms hover wait.
    private var delayTask: Task<Void, Never>?

    /// Lazily-created window-based tooltip renderer.
    /// Excluded from observation: it's an internal renderer, not part of the
    /// model's observed state, and `@Observable`'s `@ObservationTracked` macro
    /// rejects `lazy` stored properties.
    @ObservationIgnored
    private lazy var controller = TooltipWindowController()

    func requestShow(id: UUID, label: String, shortcut: [String], anchor: CGRect) {
        delayTask?.cancel()
        pending = id

        // Sibling-fluidity: if anything is already visible, swap instantly.
        if visible != nil {
            present(Tip(id: id, label: label, shortcut: shortcut, anchor: anchor))
            return
        }

        delayTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            guard let self else { return }
            guard self.pending == id else { return }
            self.present(Tip(id: id, label: label, shortcut: shortcut, anchor: anchor))
        }
    }

    /// Update only the anchor for the in-flight or visible tip with this id.
    /// Used when the button frame changes mid-hover (layout shifts, scrolling).
    /// Hot path: PreferenceKey callbacks fire on every layout tick, so we
    /// avoid `orderFront` thrash by reusing the already-presented window and
    /// only repositioning it.
    func updateAnchorIfNeeded(id: UUID, anchor: CGRect) {
        guard let tip = visible, tip.id == id, tip.anchor != anchor else { return }
        let updated = Tip(id: tip.id, label: tip.label, shortcut: tip.shortcut, anchor: anchor)
        visible = updated
        guard let panel = NSApp.windows.first(where: { $0 is MarcdownPanel }) else { return }
        controller.updateAnchor(anchorInPanel: anchor, panel: panel)
    }

    func requestHide(id: UUID) {
        if pending == id {
            delayTask?.cancel()
            pending = nil
        }
        if visible?.id == id {
            visible = nil
            controller.hide()
        }
    }

    func hideAll() {
        delayTask?.cancel()
        pending = nil
        visible = nil
        controller.hide()
    }

    // MARK: - Private

    private func present(_ tip: Tip) {
        visible = tip
        guard let panel = NSApp.windows.first(where: { $0 is MarcdownPanel }) else {
            // Panel isn't onscreen — silently skip; the next show will retry.
            return
        }
        controller.show(
            label: tip.label,
            shortcut: tip.shortcut,
            anchorInPanel: tip.anchor,
            panel: panel
        )
    }
}

// MARK: - Tooltip view

/// PreferenceKey reporting the measured size of the visible rounded rect.
/// Used by `TooltipWindowController` to size its window to exactly the visible
/// content, bypassing any padding `NSHostingView.fittingSize` may include.
private struct TooltipSizeKey: PreferenceKey {
    static let defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

/// Pure presentation: dark flat capsule with the label and zero or more
/// keycap pills, exactly per the design spec.
///
/// Reports its own measured size via `TooltipSizeKey` so the hosting window
/// can be sized to the rounded-rect bounds rather than to whatever extra
/// height `NSHostingView` chooses to expose.
struct RaycastTooltip: View {
    let label: String
    let shortcut: [String]
    var onMeasure: ((CGSize) -> Void)? = nil

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(Color.white.opacity(0.92))
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            if !shortcut.isEmpty {
                HStack(spacing: 3) {
                    ForEach(Array(shortcut.enumerated()), id: \.offset) { _, key in
                        Text(key)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.92))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(Color.white.opacity(0.12))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
                            )
                    }
                }
                .fixedSize()
                .layoutPriority(1)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(white: 0.13))
        )
        .fixedSize()
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: TooltipSizeKey.self, value: proxy.size)
            }
        )
        .onPreferenceChange(TooltipSizeKey.self) { size in
            onMeasure?(size)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Window-based renderer

/// Hosts a single `RaycastTooltip` view inside a borderless, transparent,
/// click-through `NSWindow` floating above the panel. Using a separate window
/// lets the tooltip extend past the panel's content bounds, which the previous
/// in-panel overlay could not do.
@MainActor
final class TooltipWindowController {
    private let window: NSWindow
    private let hosting: NSHostingView<RaycastTooltip>

    /// Most recent size reported by `TooltipSizeKey` — i.e. the actual
    /// rendered size of the rounded rect. Updated synchronously during
    /// `layoutSubtreeIfNeeded()` in `show(...)`.
    private var measuredSize: CGSize = .zero

    init() {
        // Order matters: `safeAreaRegions = []` must be set before
        // `sizingOptions` so the hosting view's fitting calculations don't
        // include any safe-area padding.
        let hosting = NSHostingView(rootView: RaycastTooltip(label: "", shortcut: []))
        hosting.safeAreaRegions = []
        hosting.sizingOptions = [.intrinsicContentSize]
        self.hosting = hosting

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        // `.statusBar` (25) sits above the floating MarcdownPanel (`.floating` = 3)
        // but below the host app's real menus, unlike `.popUpMenu` (101) which
        // would draw over them.
        window.level = .statusBar
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.contentView = hosting

        self.window = window
    }

    /// Show the tooltip with `label`/`shortcut`, positioning it relative to a
    /// button rect expressed in the `panel`'s coordinate space.
    func show(label: String, shortcut: [String], anchorInPanel: CGRect, panel: NSWindow) {
        // Inject a measurement callback that captures the rounded-rect's true
        // bounds via SwiftUI's GeometryReader. This is more reliable than
        // `hosting.fittingSize`, which can include padding/safe-area space.
        hosting.rootView = RaycastTooltip(
            label: label,
            shortcut: shortcut,
            onMeasure: { [weak self] size in
                self?.measuredSize = size
            }
        )
        hosting.layoutSubtreeIfNeeded()

        guard let frame = computeFrame(anchorInPanel: anchorInPanel, panel: panel) else { return }
        window.setFrame(frame, display: true)
        if !window.isVisible {
            window.orderFront(nil)
        }
    }

    /// Reposition an already-visible tooltip without re-rendering the hosting
    /// view or calling `orderFront`. No-op if the window isn't visible.
    func updateAnchor(anchorInPanel: CGRect, panel: NSWindow) {
        guard window.isVisible else { return }
        guard let frame = computeFrame(anchorInPanel: anchorInPanel, panel: panel) else { return }
        window.setFrame(frame, display: true)
    }

    func hide() {
        if window.isVisible {
            window.orderOut(nil)
        }
    }

    // MARK: - Private

    /// Compute the screen-space frame for the tooltip given a button rect in
    /// the SwiftUI `"panel"` coordinate space and the hosting panel window.
    /// Uses the most recently `measuredSize` from the hosting view; falls back
    /// to `hosting.fittingSize` if measurement hasn't yet fired.
    private func computeFrame(anchorInPanel: CGRect, panel: NSWindow) -> NSRect? {
        // Prefer the GeometryReader-reported size; fall back to fittingSize
        // only if the preference hasn't fired yet (first frame edge case).
        let size =
            measuredSize.width > 0 && measuredSize.height > 0
            ? measuredSize
            : hosting.fittingSize
        guard size.width > 0, size.height > 0 else { return nil }

        // Convert the button rect from the SwiftUI "panel" coordinate space to
        // screen coordinates. SwiftUI's named coord space sits on the root,
        // whose backing `NSHostingView` (the panel's flipped contentView) uses
        // y-down. AppKit window/screen coords are y-up, so we flip y manually
        // (minY-from-top → minY-from-bottom) using the contentView's height,
        // then map directly to screen via `panel.convertToScreen`. We do NOT
        // route through `contentView.convert(_:to:)` — on a flipped contentView
        // that call performs its own y-flip and would cancel ours, producing
        // the bug where the tooltip sticks to the bottom-right of the window.
        guard let contentView = panel.contentView else { return nil }
        let contentHeight = contentView.bounds.height
        // The "panel" named coordinate space is anchored at SwiftUI's safe-area
        // top, not at the contentView's top. Buttons rendered into the title-bar
        // zone via `.ignoresSafeArea(.top)` report negative y values in that
        // space. Add the safe-area top inset so the y-flip lands in contentView
        // coordinates (y-down from contentView top), which is what
        // `panel.convertToScreen` expects for a flipped contentView.
        let safeAreaTop = contentView.safeAreaInsets.top
        let buttonInWindow = NSRect(
            x: anchorInPanel.minX,
            y: contentHeight - (anchorInPanel.maxY + safeAreaTop),
            width: anchorInPanel.width,
            height: anchorInPanel.height
        )
        let buttonOnScreen = panel.convertToScreen(buttonInWindow)

        let gap: CGFloat = 2
        let inset: CGFloat = 8

        let buttonCenterX = buttonOnScreen.midX
        let buttonTopY = buttonOnScreen.maxY  // top edge in screen coords (y up)
        let buttonBottomY = buttonOnScreen.minY  // bottom edge in screen coords (y up)

        // Place tooltip's bottom-center 6pt above the button's top-center.
        var originX = buttonCenterX - size.width / 2
        var originY = buttonTopY + gap

        // Clamp horizontally to the screen's visible frame, leaving an 8pt inset.
        let screenFrame = panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        if screenFrame.width > 0 {
            let minX = screenFrame.minX + inset
            let maxX = screenFrame.maxX - inset - size.width
            if maxX >= minX {
                originX = max(minX, min(originX, maxX))
            }
        }

        // If there isn't enough room above the button, fall back to below.
        if screenFrame.height > 0,
            originY + size.height > screenFrame.maxY - inset
        {
            let belowY = buttonBottomY - gap - size.height
            if belowY >= screenFrame.minY + inset {
                originY = belowY
            }
        }

        return NSRect(x: originX, y: originY, width: size.width, height: size.height)
    }
}

// MARK: - Modifier

/// Attach a Raycast-style tooltip to any view (typically a `Button`).
/// The modifier:
/// - reads the view's frame in the `"panel"` coordinate space
/// - publishes hover enter/exit to the environment `TooltipModel`
/// - hides the tooltip on tap so it doesn't linger after a click triggers a sheet/palette
private struct RaycastTooltipModifier: ViewModifier {
    let label: String
    let shortcut: [String]

    @Environment(TooltipModel.self) private var model
    @State private var id = UUID()
    @State private var frame: CGRect = .zero

    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .preference(
                            key: TooltipFrameKey.self,
                            value: proxy.frame(in: .named(PanelCoordinateSpace.name))
                        )
                }
            )
            .onPreferenceChange(TooltipFrameKey.self) { newFrame in
                Task { @MainActor in
                    self.frame = newFrame
                    self.model.updateAnchorIfNeeded(id: self.id, anchor: newFrame)
                }
            }
            .onHover { hovering in
                if hovering {
                    model.requestShow(id: id, label: label, shortcut: shortcut, anchor: frame)
                } else {
                    model.requestHide(id: id)
                }
            }
            .simultaneousGesture(
                TapGesture().onEnded { model.hideAll() }
            )
    }
}

private struct TooltipFrameKey: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

extension View {
    /// Attach a Raycast-style custom tooltip. Requires a `TooltipModel` in the
    /// environment and a `.coordinateSpace(name: PanelCoordinateSpace.name)`
    /// somewhere up the hierarchy (see `PanelRootView`).
    func raycastTooltip(label: String, shortcut: [String]) -> some View {
        modifier(RaycastTooltipModifier(label: label, shortcut: shortcut))
    }
}

// MARK: - Coordinate space

/// Centralised coordinate-space name so the modifier and the panel root agree.
enum PanelCoordinateSpace {
    static let name = "panel"
}
