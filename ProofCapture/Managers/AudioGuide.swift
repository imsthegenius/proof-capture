import AVFoundation
import AudioToolbox
import Foundation

enum GuidanceMode: Int {
    case voice = 0
    case text = 1
}

@MainActor
final class AudioGuide: NSObject, AVSpeechSynthesizerDelegate {

    private let voicePlayer = VoicePlayer()

    // Narrow fallback for dynamic strings with no matching clip.
    private lazy var synthesizer: AVSpeechSynthesizer = {
        let s = AVSpeechSynthesizer()
        s.delegate = self
        return s
    }()
    private var speechContinuation: CheckedContinuation<Void, Never>?

    var mode: GuidanceMode {
        GuidanceMode(rawValue: UserDefaults.standard.integer(forKey: "guidanceMode")) ?? .voice
    }

    // MARK: - Public API

    /// Speaks text aloud using a bundled clip if available, falling back to TTS.
    /// No-op in text mode.
    func speak(_ text: String) async {
        guard mode == .voice else { return }

        if let clip = clipForText(text) {
            await voicePlayer.play(clip)
        } else {
            await speakWithSynthesizer(text)
        }
    }

    /// Speaks positioning guidance based on current issues.
    func speakPositionGuidance(
        bodyDetected: Bool,
        positionQuality: QualityLevel,
        poseMatches: Bool,
        armsRelaxed: Bool,
        targetPose: Pose,
        detectedOrientation: Pose?
    ) async {
        guard mode == .voice else { return }

        if !bodyDetected {
            await voicePlayer.play(.guidanceNoBody)
            return
        }

        if !poseMatches, let detected = detectedOrientation {
            if let clip = orientationClip(target: targetPose, detected: detected) {
                await voicePlayer.play(clip)
            } else {
                await speakWithSynthesizer(
                    "Adjust your position for the \(targetPose.title.lowercased()) pose."
                )
            }
            return
        }

        if !armsRelaxed {
            await voicePlayer.play(.guidanceArms)
            return
        }

        if positionQuality == .poor {
            await voicePlayer.play(.guidanceAdjustPosition)
            return
        }
    }

    /// Plays a single countdown cue. Unchanged — system sounds are correct here.
    func playCountdownTick(isFinal: Bool) {
        let soundID: SystemSoundID = isFinal ? 1117 : 1057
        AudioServicesPlaySystemSound(soundID)
    }

    func speakPoseTransition(from: Pose, to: Pose) async {
        guard mode == .voice else { return }

        switch (from, to) {
        case (.front, .side):
            await voicePlayer.play(.transitionFrontToSide)
        case (.side, .back):
            await voicePlayer.play(.transitionSideToBack)
        default:
            await speakWithSynthesizer("Next pose. Show your \(to.title.lowercased()) pose.")
        }
    }

    func speakSessionComplete() async {
        guard mode == .voice else { return }
        await voicePlayer.play(.sessionComplete)
    }

    /// Speaks lighting guidance when flat lighting is detected.
    func speakLightingGuidance() async {
        guard mode == .voice else { return }
        await voicePlayer.play(.guidanceOverhead)
    }

    /// Stops any current speech or playback immediately.
    func stop() {
        Task { await voicePlayer.stop() }
        synthesizer.stopSpeaking(at: .immediate)
        speechContinuation?.resume()
        speechContinuation = nil
    }

    // MARK: - Clip Matching

    private func clipForText(_ text: String) -> VoiceClip? {
        switch text {
        case Pose.front.audioPrompt: return .poseFront
        case Pose.side.audioPrompt:  return .poseSide
        case Pose.back.audioPrompt:  return .poseBack
        default:                     return nil
        }
    }

    private func orientationClip(target: Pose, detected: Pose) -> VoiceClip? {
        switch (target, detected) {
        case (.front, .side):  return .orientFrontFromSide
        case (.front, .back):  return .orientFrontFromBack
        case (.side, .front):  return .orientSideFromFront
        case (.side, .back):   return .orientSideFromBack
        case (.back, .front):  return .orientBackFromFront
        case (.back, .side):   return .orientBackFromSide
        default:               return nil
        }
    }

    // MARK: - AVSpeechSynthesizer Fallback

    private func speakWithSynthesizer(_ text: String) async {
        synthesizer.stopSpeaking(at: .immediate)

        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = 0.46
        utterance.pitchMultiplier = 1.0
        utterance.preUtteranceDelay = 0.1
        utterance.voice = AVSpeechSynthesisVoice(language: "en-GB")

        await withCheckedContinuation { continuation in
            speechContinuation = continuation
            synthesizer.speak(utterance)
        }
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
