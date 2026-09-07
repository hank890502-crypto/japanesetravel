import Foundation
import os
import UIKit

/// 依設定把 AI 呼叫轉給對應的實作。設定改了立刻生效，不用重開 App。
final class AIServiceRouter: AIService, @unchecked Sendable {
    private struct Selection {
        var kind: AIProviderKind
        var backendURL: URL?
    }

    private let lock = OSAllocatedUnfairLock(initialState: Selection(kind: .disabled, backendURL: nil))
    private let disabled = DisabledAIService()
    private let mock = MockAIService()

    init(kind: AIProviderKind = .disabled, backendURL: URL? = nil) {
        lock.withLock { $0 = Selection(kind: kind, backendURL: backendURL) }
    }

    func update(kind: AIProviderKind, backendURL: URL?) {
        lock.withLock { $0 = Selection(kind: kind, backendURL: backendURL) }
    }

    var currentKind: AIProviderKind { lock.withLock { $0.kind } }

    private var current: any AIService {
        let selection = lock.withLock { $0 }
        switch selection.kind {
        case .disabled: return disabled
        case .mock: return mock
        case .appleIntelligence:
            #if canImport(FoundationModels)
            if #available(iOS 26, *), AppleIntelligence.availability.isAvailable {
                return AppleIntelligenceAIService()
            }
            #endif
            return disabled
        case .remoteBackend:
            guard let url = selection.backendURL else { return disabled }
            return RemoteAIService(baseURL: url)
        }
    }

    var isEnabled: Bool { current.isEnabled }
    var providerName: String { current.providerName }

    func analyzeMenu(textBlocks: [RecognizedTextBlock], image: UIImage?) async throws -> MenuAnalysis {
        try await current.analyzeMenu(textBlocks: textBlocks, image: image)
    }
    func analyzeProduct(image: UIImage) async throws -> ProductAnalysis {
        try await current.analyzeProduct(image: image)
    }
    func analyzeReceipt(image: UIImage) async throws -> ReceiptAnalysis {
        try await current.analyzeReceipt(image: image)
    }
    func translate(_ text: String, to language: TranslationLanguage) async throws -> Translation {
        try await current.translate(text, to: language)
    }
}
