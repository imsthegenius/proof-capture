import Foundation

// MARK: - User Gender

enum UserGender: Int {
    case male = 0
    case female = 1
}

// MARK: - User Preferences

/// Namespace for UserDefaults-backed preferences set during onboarding.
/// Views should use @AppStorage directly for reactivity; these static
/// accessors are for non-view code (managers, services).
enum UserPreferences {

    // MARK: Keys

    private enum Key {
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let genderRaw = "genderRaw"
        static let countdownSeconds = "countdownSeconds"
    }

    // MARK: Stored Properties

    static var hasCompletedOnboarding: Bool {
        get { UserDefaults.standard.bool(forKey: Key.hasCompletedOnboarding) }
        set { UserDefaults.standard.set(newValue, forKey: Key.hasCompletedOnboarding) }
    }

    static var genderRaw: Int {
        get { UserDefaults.standard.integer(forKey: Key.genderRaw) }
        set { UserDefaults.standard.set(newValue, forKey: Key.genderRaw) }
    }

    static var countdownSeconds: Int {
        get {
            let value = UserDefaults.standard.integer(forKey: Key.countdownSeconds)
            return value == 0 ? 5 : value
        }
        set { UserDefaults.standard.set(newValue, forKey: Key.countdownSeconds) }
    }

    // MARK: Computed

    static var gender: UserGender {
        UserGender(rawValue: genderRaw) ?? .male
    }
}
