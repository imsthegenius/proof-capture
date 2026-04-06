import Foundation
import OSLog
import Supabase

enum AppSupabase {
    static let client: SupabaseClient? = makeClient()

    private static let logger = Logger(subsystem: "com.proof.capture", category: "SupabaseConfig")

    private static func makeClient() -> SupabaseClient? {
        guard let urlString = configurationString(for: "SUPABASE_URL"),
              let url = URL(string: urlString),
              url.host != nil else {
            logger.warning("Supabase URL missing or invalid — running offline-only")
            return nil
        }

        guard let key = configurationString(for: "SUPABASE_ANON_KEY"),
              key != "your-anon-key-here" else {
            logger.warning("Supabase anon key missing or placeholder — running offline-only")
            return nil
        }

        let redirectURL = configurationURL(for: "SUPABASE_REDIRECT_URL")

        return SupabaseClient(
            supabaseURL: url,
            supabaseKey: key,
            options: SupabaseClientOptions(
                auth: .init(
                    redirectToURL: redirectURL,
                    flowType: .pkce
                )
            )
        )
    }

    private static func configurationString(for key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !value.isEmpty else {
            return nil
        }
        return value
    }

    private static func configurationURL(for key: String) -> URL? {
        guard let value = configurationString(for: key),
              let url = URL(string: value) else {
            return nil
        }
        return url
    }
}
