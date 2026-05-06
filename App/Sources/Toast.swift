import SwiftUI

/// A single piece of toast copy paired with how long it should remain on screen.
///
/// Identity is per-instance (a fresh `UUID` each time): two entries that share
/// text and duration are still distinct, which lets `ToastModel` invalidate a
/// pending dismissal closure by checking the live id.
struct ToastEntry: Identifiable, Equatable, Sendable {
    let id: UUID
    let text: String
    let duration: Duration

    init(text: String, duration: Duration) {
        self.id = UUID()
        self.text = text
        self.duration = duration
    }
}

/// `ToastModel` owns the at-most-one-toast state for the panel.
///
/// The auto-dismiss scheduler is injected so tests can drive timing
/// deterministically; the production default uses `Task.sleep`. The model
/// guards against stale dismissals (a superseded entry's timer firing after
/// `show(_:)` swapped in a new entry, or after `dismissNow()`) by recording
/// the live entry's id and ignoring closures whose captured id no longer
/// matches.
@MainActor
@Observable
final class ToastModel {
    private(set) var current: ToastEntry?

    private let scheduler: @MainActor (Duration, @escaping @MainActor () -> Void) -> Task<Void, Never>

    init(
        scheduler: @escaping @MainActor (Duration, @escaping @MainActor () -> Void) -> Task<Void, Never> = { duration, fire in
            Task { @MainActor in
                try? await Task.sleep(for: duration)
                fire()
            }
        }
    ) {
        self.scheduler = scheduler
    }

    func show(_ entry: ToastEntry) {
        current = entry
        let liveID = entry.id
        _ = scheduler(entry.duration) { [weak self] in
            guard let self else { return }
            // Ignore stale fires: only clear if this entry is still the live one.
            if self.current?.id == liveID {
                self.current = nil
            }
        }
    }

    func dismissNow() {
        current = nil
    }
}

/// HUD-style toast surface. Fixed-dark in both appearances per DESIGN.md
/// `component.toast` — this is a transient overlay artifact, not chrome that
/// follows the system appearance.
struct Toast: View {
    let model: ToastModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if let entry = model.current {
                Text(entry.text)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.92))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color(white: 0.13))
                    )
                    .transition(
                        .opacity.animation(reduceMotion ? nil : .easeOut(duration: 0.15))
                    )
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(entry.text)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: model.current?.id)
    }
}
