import SwiftUI

/// 「我要跟人說話」：先選情境。
struct CommunicationCategoriesView: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text("你現在在哪裡？")
                    .font(.app(.body))
                    .foregroundStyle(AppColors.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ForEach(PhraseCategory.allCases) { category in
                    LargeActionCard(
                        title: category.displayName,
                        subtitle: category.subtitle,
                        systemImage: category.systemImage,
                        tint: category == .emergency ? AppColors.help : AppColors.talk
                    ) {
                        router.push(.phraseList(category))
                    }
                }
            }
            .padding(AccessibilityMetrics.screenPadding)
        }
        .elderlyScreen(title: "我要跟人說話")
    }
}

#Preview {
    NavigationStack {
        CommunicationCategoriesView()
    }
    .environment(AppRouter())
    .environment(\.dependencies, .preview)
}
