import Foundation
import Testing

@testable import Marcdown

/// `ToastModel` is a `@MainActor`-isolated controller, so tests must run on the
/// main actor. We inject a fake scheduler into the model so the auto-dismiss
/// behaviour is deterministic — production scheduling is `Task.sleep`-based and
/// would make tests timing-dependent.
@MainActor
@Suite("ToastModel")
struct ToastModelTests {
    /// Records every `(duration, fire)` pair handed to `ToastModel`'s scheduler.
    /// `fire()` runs the dismissal closure synchronously, simulating the timer
    /// firing. The model is responsible for ignoring stale fires after a swap
    /// or `dismissNow()`.
    @MainActor
    final class FakeScheduler {
        struct Scheduled {
            let duration: Duration
            let fire: @MainActor () -> Void
        }
        private(set) var scheduled: [Scheduled] = []

        var scheduler: @MainActor (Duration, @escaping @MainActor () -> Void) -> Task<Void, Never> {
            { [weak self] duration, closure in
                self?.scheduled.append(Scheduled(duration: duration, fire: closure))
                // Return a no-op task so the production signature is preserved
                // without the test ever waiting on real time.
                return Task { }
            }
        }

        var lastDuration: Duration? { scheduled.last?.duration }

        func fireLast() {
            guard let last = scheduled.last else { return }
            last.fire()
        }

        func fireAt(_ index: Int) {
            scheduled[index].fire()
        }
    }

    @Test("Fresh model has no current toast")
    func initialCurrentIsNil() {
        let fake = FakeScheduler()
        let model = ToastModel(scheduler: fake.scheduler)
        #expect(model.current == nil)
    }

    @Test("show(_:) sets the current entry")
    func showSetsCurrent() {
        let fake = FakeScheduler()
        let model = ToastModel(scheduler: fake.scheduler)
        let entry = ToastEntry(text: "Saved", duration: .milliseconds(1500))

        model.show(entry)

        #expect(model.current?.id == entry.id)
        #expect(model.current?.text == "Saved")
    }

    @Test("Auto-dismiss clears current after the scheduled duration fires")
    func autoDismissAfterDuration() {
        let fake = FakeScheduler()
        let model = ToastModel(scheduler: fake.scheduler)
        let entry = ToastEntry(text: "Saved", duration: .milliseconds(1500))

        model.show(entry)
        fake.fireLast()

        #expect(model.current == nil)
    }

    /// Critical correctness test: a stale dismissal from a superseded entry
    /// must not clear the new toast. Without per-show invalidation, swapping
    /// toasts in quick succession would cause the second one to vanish as
    /// soon as the first one's timer fires.
    @Test("show replaces a live toast and invalidates the prior dismissal")
    func secondShowReplacesFirstImmediately() {
        let fake = FakeScheduler()
        let model = ToastModel(scheduler: fake.scheduler)
        let first = ToastEntry(text: "First", duration: .seconds(4))
        let second = ToastEntry(text: "Second", duration: .milliseconds(1500))

        model.show(first)
        model.show(second)

        #expect(model.current?.id == second.id)

        // Fire the *first* entry's stale dismissal — the model must ignore it.
        fake.fireAt(0)
        #expect(model.current?.id == second.id)
    }

    @Test("dismissNow clears the current entry")
    func dismissNowClearsCurrent() {
        let fake = FakeScheduler()
        let model = ToastModel(scheduler: fake.scheduler)
        let entry = ToastEntry(text: "Saved", duration: .seconds(4))

        model.show(entry)
        model.dismissNow()

        #expect(model.current == nil)
    }

    @Test("dismissNow cancels the pending auto-dismiss")
    func dismissNowCancelsPendingAutoDismiss() {
        let fake = FakeScheduler()
        let model = ToastModel(scheduler: fake.scheduler)
        let entry = ToastEntry(text: "Saved", duration: .seconds(4))

        model.show(entry)
        model.dismissNow()
        // Firing the stale closure must be a no-op (and must not crash).
        fake.fireLast()

        #expect(model.current == nil)
    }

    @Test("show forwards the entry's duration to the scheduler unchanged")
    func entryDurationIsRespected() {
        let fake = FakeScheduler()
        let model = ToastModel(scheduler: fake.scheduler)
        let entry = ToastEntry(text: "Saved", duration: .milliseconds(1500))

        model.show(entry)

        #expect(fake.lastDuration == .milliseconds(1500))
    }

    @Test("Two ToastEntry values with identical fields receive distinct ids")
    func entryHasUniqueIDs() {
        let a = ToastEntry(text: "x", duration: .seconds(1))
        let b = ToastEntry(text: "x", duration: .seconds(1))
        #expect(a.id != b.id)
    }
}
