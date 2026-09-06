import Foundation

enum SpeechLanguage: String, Sendable {
    case japanese = "ja-JP"
    case traditionalChinese = "zh-TW"
}

/// 語音播放。M1 加入 AVSpeechService（AVSpeechSynthesizer）。
protocol SpeechService: Sendable {
    var isAvailable: Bool { get }
    func speak(_ text: String, language: SpeechLanguage) async
    func stop() async
}

/// 尚未實作／不支援時的空實作。
struct NoopSpeechService: SpeechService {
    var isAvailable: Bool { false }
    func speak(_ text: String, language: SpeechLanguage) async {}
    func stop() async {}
}
