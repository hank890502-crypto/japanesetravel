import SwiftUI
import UIKit

/// 「我遇到問題」：最上面是打電話，下面是依場面分類的緊急句子。
struct EmergencyView: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.dependencies) private var dependencies
    @State private var phrases: [Phrase] = []
    @State private var selectedScene = EmergencyView.allScenes

    private static let allScenes = "__all__"

    private struct EmergencyNumber: Identifiable {
        let id: String
        let title: String
        let subtitle: String
    }

    private let numbers = [
        EmergencyNumber(id: "119", title: "打 119", subtitle: "救護車、火災（日本）"),
        EmergencyNumber(id: "110", title: "打 110", subtitle: "警察（日本）"),
    ]

    private var scenes: [String] { phrases.scenes }
    private var visible: [Phrase] {
        selectedScene == Self.allScenes ? phrases : phrases.filter { $0.scene == selectedScene }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16, pinnedViews: [.sectionHeaders]) {
                ForEach(numbers) { number in
                    LargeActionCard(title: number.title, subtitle: number.subtitle, systemImage: AppIcon.phone, tint: AppColors.help) {
                        call(number.id)
                    }
                }

                Section {
                    Text("把句子拿給旁邊的人看，點一下會變大字。")
                        .font(.app(.body))
                        .foregroundStyle(AppColors.secondaryText)
                    ForEach(visible) { phrase in
                        JapanesePhraseCard(phrase: phrase) {
                            router.showToStaff(StaffDisplayContent(phrase: phrase))
                        }
                    }
                } header: {
                    if scenes.count > 1 {
                        CategoryChipBar(
                            chips: [.init(id: Self.allScenes, title: "全部")] + scenes.map { .init(id: $0, title: $0) },
                            selectedId: $selectedScene
                        )
                        .padding(.horizontal, -AccessibilityMetrics.screenPadding)
                    }
                }
            }
            .padding(.horizontal, AccessibilityMetrics.screenPadding)
            .padding(.bottom, AccessibilityMetrics.screenPadding)
        }
        .elderlyScreen(title: "我遇到問題")
        .task {
            phrases = (try? await dependencies.phrases.phrases(in: .emergency)) ?? []
            if let first = scenes.first, scenes.count > 1 { selectedScene = first }
        }
    }

    private func call(_ number: String) {
        guard let url = URL(string: "tel://\(number)") else { return }
        UIApplication.shared.open(url)
    }
}

#Preview {
    NavigationStack { EmergencyView() }
        .environment(AppRouter())
        .environment(\.dependencies, .preview)
}
