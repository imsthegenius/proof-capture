import AVFoundation

/// Pre-recorded voice clip identifiers. Each case maps to a bundled .m4a file,
/// with male (default) and female variants selected by user preference.
enum VoiceClip: String, CaseIterable {
    // Pose prompts
    case poseFront = "pose_front"
    case poseSide = "pose_side"
    case poseBack = "pose_back"

    // Positioning guidance
    case guidanceNoBody = "guidance_no_body"
    case guidanceArms = "guidance_arms"
    case guidanceAdjustPosition = "guidance_adjust_position"
    case guidanceOverhead = "guidance_overhead"

    // Orientation corrections
    case orientFrontFromSide = "orient_front_from_side"
    case orientFrontFromBack = "orient_front_from_back"
    case orientSideFromFront = "orient_side_from_front"
    case orientSideFromBack = "orient_side_from_back"
    case orientBackFromFront = "orient_back_from_front"
    case orientBackFromSide = "orient_back_from_side"

    // Transitions
    case transitionFrontToSide = "transition_front_to_side"
    case transitionSideToBack = "transition_side_to_back"

    // Session
    case sessionComplete = "session_complete"

    /// Returns the filename for the selected gender.
    /// Male (0/default) uses the base name, female (1) uses the f_ prefix.
    func filename(forGender genderRaw: Int) -> String {
        genderRaw == 1 ? "f_\(rawValue)" : rawValue
    }
}

/// Plays bundled .m4a voice guidance clips with zero latency.
/// Designed to coexist with AVCaptureSession's audio session.
@MainActor
final class VoicePlayer: NSObject, AVAudioPlayerDelegate {

    private var player: AVAudioPlayer?
    private var playbackContinuation: CheckedContinuation<Void, Never>?

    /// Plays a clip for the user's selected guide voice gender and suspends until done.
    func play(_ clip: VoiceClip) async {
        stop()

        let genderRaw = UserDefaults.standard.integer(forKey: "userGender")
        let name = clip.filename(forGender: genderRaw)

        guard let url = Bundle.main.url(forResource: name, withExtension: "m4a") else {
            return
        }

        guard let audioPlayer = try? AVAudioPlayer(contentsOf: url) else {
            return
        }

        configureAudioSession()

        audioPlayer.delegate = self
        audioPlayer.prepareToPlay()
        player = audioPlayer

        await withCheckedContinuation { continuation in
            playbackContinuation = continuation
            audioPlayer.play()
        }
    }

    /// Stops current playback immediately and resumes any waiting caller.
    func stop() {
        player?.stop()
        player = nil
        playbackContinuation?.resume()
        playbackContinuation = nil
    }

    // MARK: - Audio Session

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        // .playback + .duckOthers lets guidance play over background music
        // without interrupting the camera's audio session.
        try? session.setCategory(.playback, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
        try? session.setActive(true)
    }

    // MARK: - AVAudioPlayerDelegate

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        MainActor.assumeIsolated {
            playbackContinuation?.resume()
            playbackContinuation = nil
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: (any Error)?) {
        MainActor.assumeIsolated {
            playbackContinuation?.resume()
            playbackContinuation = nil
        }
    }
}
