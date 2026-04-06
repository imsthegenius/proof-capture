import AVFoundation
import os

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

private let audioLog = Logger(subsystem: "com.proof.capture", category: "VoicePlayer")

/// Plays bundled .m4a voice guidance clips with zero latency.
/// Designed to coexist with AVCaptureSession's audio session.
actor VoicePlayer {

    private var player: AVAudioPlayer?

    /// Plays a clip for the user's selected guide voice gender and suspends until done.
    func play(_ clip: VoiceClip) async {
        stop()

        let genderRaw = await MainActor.run {
            UserDefaults.standard.integer(forKey: "userGender")
        }
        let name = clip.filename(forGender: genderRaw)

        guard let url = Bundle.main.url(forResource: name, withExtension: "m4a") else {
            audioLog.warning("Missing audio clip: \(name).m4a")
            return
        }

        let audioPlayer: AVAudioPlayer
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
        } catch {
            audioLog.error("Failed to create AVAudioPlayer for \(name).m4a: \(error.localizedDescription)")
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
            try session.setActive(true)
        } catch {
            audioLog.error("AVAudioSession configuration failed: \(error.localizedDescription)")
            return
        }

        audioPlayer.prepareToPlay()
        player = audioPlayer

        guard audioPlayer.play() else {
            audioLog.error("AVAudioPlayer.play() returned false for \(name).m4a")
            player = nil
            return
        }

        // Wait for the clip to finish. Duration-based sleep is reliable
        // for short, fixed-length clips where delegate wiring across
        // actor isolation would add unnecessary complexity.
        if audioPlayer.duration > 0 {
            try? await Task.sleep(for: .seconds(audioPlayer.duration + 0.05))
        }

        player = nil
    }

    /// Stops current playback immediately.
    func stop() {
        player?.stop()
        player = nil
    }
}
