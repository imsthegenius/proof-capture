import Supabase
import Foundation

enum AppSupabase {
    private static let supabaseURL = configurationURL(for: "SUPABASE_URL")
    private static let supabaseKey = configurationString(for: "SUPABASE_ANON_KEY")
    private static let redirectToURL = configurationURL(for: "SUPABASE_REDIRECT_URL")

    static let client = SupabaseClient(
        supabaseURL: supabaseURL,
        supabaseKey: supabaseKey,
        options: SupabaseClientOptions(
            auth: .init(
                redirectToURL: redirectToURL,
                flowType: .pkce
            )
        )
    )

    private static func configurationString(for key: String) -> String {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !value.isEmpty else {
            fatalError("Missing required Info.plist value for \(key)")
        }

        return value
    }

    private static func configurationURL(for key: String) -> URL {
        let value = configurationString(for: key)

        guard let url = URL(string: value) else {
            fatalError("Invalid Info.plist URL value for \(key)")
        }

        return url
    }
}
