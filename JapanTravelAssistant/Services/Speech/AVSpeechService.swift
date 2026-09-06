import AVFoundation
import Foundation

/// 用 iOS 內建的語音合成朗讀日文。離線可用，不需要任何 API。
/// 會把音訊類別設成 playback，讓手機在靜音模式下也能發出聲音（給店員聽很重要）。
@MainActor
final class AVSpeechService: NSObject, SpeechService {
    private let synthesizer = AVSpeechSynthesizer()
    private var continuation: CheckedContinuation<Void, Never>?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    nonisolated var isAvailable: Bool {
        AVSpeechSynthesisVoice(language: SpeechLanguage.japanese.rawValue) != nil
    }

    func speak(_ text: String, language: SpeechLanguage) async {
        await stop()

        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? session.setActive(true, options: [])

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: language.rawValue)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.85  // 稍慢，聽得清楚
        utterance.postUtteranceDelay = 0.2

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            continuation = cont
            synthesizer.speak(utterance)
        }
    }

    func stop() async {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        finish()
    }

    private func finish() {
        continuation?.resume()
        continuation = nil
    }
}

extension AVSpeechService: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.finish() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.finish() }
    }
}
