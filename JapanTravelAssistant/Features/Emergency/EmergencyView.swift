import SwiftUI
import UIKit

/// 「我遇到問題」：最上面是打電話，下面是可以給人看的緊急句子。
struct EmergencyView: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.dependencies) private var dependencies
    @State private var phrases: [Phrase] = []

    private struct EmergencyNumber: Identifiable {
        let id: String
        let title: String
        let subtitle: String
    }

    private let numbers = [
        EmergencyNumber(id: "119", title: "打 119", subtitle: "救護車、火災（日本）"),
        EmergencyNumber(id: "110", title: "打 110", subtitle: "警察（日本）"),
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ForEach(numbers) { number in
                    LargeActionCard(
                        title: number.title,
                        subtitle: number.subtitle,
                        systemImage: AppIcon.phone,
                        tint: AppColors.help
                    ) {
                        call(number.id)
                    }
                }

                Text("或是把下面的句子拿給旁邊的人看：")
                    .font(.app(.body))
                    .foregroundStyle(AppColors.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)

                ForEach(phrases) { phrase in
                    JapanesePhraseCard(phrase: phrase) {
                        router.showToStaff(StaffDisplayContent(phrase: phrase))
                    }
                }
            }
            .padding(AccessibilityMetrics.screenPadding)
        }
        .elderlyScreen(title: "我遇到問題")
        .task {
            phrases = (try? await dependencies.phrases.phrases(in: .emergency)) ?? []
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
