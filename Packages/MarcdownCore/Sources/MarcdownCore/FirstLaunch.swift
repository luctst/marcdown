import Foundation

/// Key used to persist whether the app has been launched before.
public let firstLaunchDefaultsKey = "dev.marcdown.hasLaunched"

/// Returns `true` if the app has never been launched before.
public func isFirstLaunch(defaults: UserDefaults) -> Bool {
    !defaults.bool(forKey: firstLaunchDefaultsKey)
}

/// Persists that the app has been launched. Subsequent calls to
/// `isFirstLaunch(defaults:)` with the same suite will return `false`.
public func markLaunched(defaults: UserDefaults) {
    defaults.set(true, forKey: firstLaunchDefaultsKey)
}
