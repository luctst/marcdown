import Foundation
import Testing

@testable import MarcdownCore

@Suite("First launch detection")
struct FirstLaunchTests {
    private func makeIsolatedDefaults(
        _ label: String = #function
    ) -> UserDefaults {
        let suiteName = "dev.marcdown.tests.\(label).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    @Test("Reports first launch when the flag is absent")
    func firstLaunchWhenFlagAbsent() {
        let defaults = makeIsolatedDefaults()
        #expect(isFirstLaunch(defaults: defaults) == true)
    }

    @Test("Reports not first launch after markLaunched")
    func notFirstLaunchAfterMark() {
        let defaults = makeIsolatedDefaults()
        markLaunched(defaults: defaults)
        #expect(isFirstLaunch(defaults: defaults) == false)
    }

    @Test("markLaunched is idempotent")
    func markLaunchedIsIdempotent() {
        let defaults = makeIsolatedDefaults()
        markLaunched(defaults: defaults)
        markLaunched(defaults: defaults)
        #expect(isFirstLaunch(defaults: defaults) == false)
    }

    @Test("Independent suites do not share state")
    func independentSuitesAreIsolated() {
        let suiteA = makeIsolatedDefaults("suiteA")
        let suiteB = makeIsolatedDefaults("suiteB")
        markLaunched(defaults: suiteA)
        #expect(isFirstLaunch(defaults: suiteA) == false)
        #expect(isFirstLaunch(defaults: suiteB) == true)
    }
}
