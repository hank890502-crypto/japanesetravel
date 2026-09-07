import Foundation

/// 溝通助手的句子來源。目前從 App 內建的 phrases.json 讀取；未來可換成可更新的遠端資料。
protocol PhraseProvider: Sendable {
    func phrases(in category: PhraseCategory) async throws -> [Phrase]
    func phrases(ids: [String]) async throws -> [Phrase]
}

extension Array where Element == Phrase {
    /// 場面名稱，依第一次出現的順序
    var scenes: [String] {
        var seen = Set<String>()
        return compactMap { phrase in
            guard let scene = phrase.scene?.nilIfBlank, !seen.contains(scene) else { return nil }
            seen.insert(scene)
            return scene
        }
    }
}

/// 讀取 Bundle 內的 phrases.json。啟動時載入一次。
final class BundledPhraseProvider: PhraseProvider {
    private let all: [Phrase]

    init(bundle: Bundle = .main) {
        guard let url = bundle.url(forResource: "phrases", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([Phrase].self, from: data)
        else {
            assertionFailure("phrases.json 載入失敗，請確認檔案在 Resources/Phrases 且格式正確")
            all = []
            return
        }
        all = decoded
    }

    func phrases(in category: PhraseCategory) async throws -> [Phrase] {
        all.filter { $0.category == category }
    }

    func phrases(ids: [String]) async throws -> [Phrase] {
        let byId = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return ids.compactMap { byId[$0] }
    }
}
