import Supabase
import Foundation

enum AppSupabase {
    static let client = SupabaseClient(
        supabaseURL: URL(string: "https://pbntloqfayegjamsvmpy.supabase.co")!,
        supabaseKey: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBibnRsb3FmYXllZ2phbXN2bXB5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQ2MTQ2NjQsImV4cCI6MjA5MDE5MDY2NH0.QxStEweDTRIefAl8bWxlaRzo8QXOIUMwrlIJgcjBPTE",
        options: SupabaseClientOptions(
            auth: .init(
                redirectToURL: URL(string: "com.proof.capture://auth-callback"),
                flowType: .pkce
            )
        )
    )
}
