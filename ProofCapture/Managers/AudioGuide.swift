import AVFoundation
import AudioToolbox

enum GuidanceMode: Int {
    case voice = 0
    case text = 1
}

@MainActor
final class AudioGuide: NSObject, AVSpeechSynthesizerDelegate {

    private let synthesizer = AVSpeechSynthesizer()
    private var speechContinuation: CheckedContinuation<Void, Never>?

    var mode: GuidanceMode {
        GuidanceMode(rawValue: UserDefaults.standard.integer(forKey: "guidanceMode")) ?? .voice
    }

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    // MARK: - Public API

    /// Speaks text aloud and waits for completion. No-op in text mode.
    func speak(_ text: String) async {
        guard mode == .voice else { return }

        synthesizer.stopSpeaking(at: .immediate)

        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = 0.46
        utterance.pitchMultiplier = 1.0
        utterance.preUtteranceDelay = 0.1

        utterance.voice = preferredVoice()

        await withCheckedContinuation { continuation in
            speechContinuation = continuation
            synthesizer.speak(utterance)
        }
    }

    /// Plays ascending countdown beeps with 1-second intervals.
    func playCountdown(seconds: Int = 3) async {
        for i in 0..<seconds {
            let isLast = (i == seconds - 1)
            let soundID: SystemSoundID = isLast ? 1117 : 1057
            AudioServicesPlaySystemSound(soundID)
            try? await Task.sleep(for: .seconds(1))
        }
    }

    /// Speaks the instruction, pauses briefly, then plays the countdown.
    func speakAndCountdown(_ text: String, countdownSeconds: Int = 3) async {
        await speak(text)
        try? await Task.sleep(for: .milliseconds(500))
        await playCountdown(seconds: countdownSeconds)
    }

    /// Stops any current speech immediately.
    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        // Resume any waiting continuation so callers don't hang
        speechContinuation?.resume()
        speechContinuation = nil
    }

    // MARK: - Voice Selection

    private func preferredVoice() -> AVSpeechSynthesisVoice? {
        let genderRaw = UserDefaults.standard.integer(forKey: "userGender")

        // Voice preference cascade: premium > enhanced > compact
        let identifiers: [String] = if genderRaw == 1 {
            // Female
            [
                "com.apple.voice.premium.en-GB.Serena",
                "com.apple.voice.enhanced.en-GB.Stephanie",
                "com.apple.voice.compact.en-GB.Stephanie",
            ]
        } else {
            // Male (default)
            [
                "com.apple.voice.premium.en-GB.Malcolm",
                "com.apple.voice.enhanced.en-GB.Daniel",
                "com.apple.voice.compact.en-GB.Daniel",
            ]
        }

        for identifier in identifiers {
            if let voice = AVSpeechSynthesisVoice(identifier: identifier) {
                return voice
            }
        }

        // Final fallback
        return AVSpeechSynthesisVoice(language: "en-GB")
    }

    // MARK: - AVSpeechSynthesizerDelegate

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        MainActor.assumeIsolated {
            speechContinuation?.resume()
            speechContinuation = nil
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        MainActor.assumeIsolated {
            speechContinuation?.resume()
            speechContinuation = nil
        }
    }
}
