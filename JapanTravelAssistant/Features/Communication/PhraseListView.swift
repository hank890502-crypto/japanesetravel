import SwiftUI

/// 某個情境的常用句子。點一句 → 全螢幕給對方看。
struct PhraseListView: View {
    let category: PhraseCategory

    @Environment(AppRouter.self) private var router
    @Environment(\.dependencies) private var dependencies
    @State private var phrases: [Phrase] = []
    @State private var error: UserFacingError?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text("點一下句子，就會用大字顯示日文給對方看。")
                    .font(.app(.body))
                    .foregroundStyle(AppColors.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let error {
                    ErrorBanner(error: error) { Task { await load() } }
                }

                ForEach(phrases) { phrase in
                    JapanesePhraseCard(phrase: phrase) {
                        router.showToStaff(StaffDisplayContent(phrase: phrase))
                    }
                }
            }
            .padding(AccessibilityMetrics.screenPadding)
        }
        .elderlyScreen(title: category.displayName)
        .task { await load() }
    }

    private func load() async {
        do {
            phrases = try await dependencies.phrases.phrases(in: category)
            error = nil
        } catch {
            self.error = UserFacingError.from(error)
        }
    }
}

#Preview {
    NavigationStack {
        PhraseListView(category: .shopping)
    }
    .environment(AppRouter())
    .environment(\.dependencies, .preview)
}
