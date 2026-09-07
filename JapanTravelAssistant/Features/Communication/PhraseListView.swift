import SwiftUI

/// 某個情境的常用句子，上方用「場面」分類列切換（入住、退房…）。點一句 → 全螢幕給對方看。
struct PhraseListView: View {
    let category: PhraseCategory

    @Environment(AppRouter.self) private var router
    @Environment(\.dependencies) private var dependencies
    @State private var phrases: [Phrase] = []
    @State private var error: UserFacingError?
    @State private var selectedScene = PhraseListView.allScenes

    private static let allScenes = "__all__"

    private var scenes: [String] { phrases.scenes }
    private var visible: [Phrase] {
        selectedScene == Self.allScenes ? phrases : phrases.filter { $0.scene == selectedScene }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16, pinnedViews: [.sectionHeaders]) {
                if let error {
                    ErrorBanner(error: error) { Task { await load() } }
                }
                Section {
                    Text("點一下句子，就會用大字顯示日文給對方看。")
                        .font(.app(.body))
                        .foregroundStyle(AppColors.secondaryText)

                    if selectedScene == Self.allScenes && scenes.count > 1 {
                        ForEach(scenes, id: \.self) { scene in
                            Text(scene)
                                .font(.app(.sectionTitle))
                                .padding(.top, 8)
                                .accessibilityAddTraits(.isHeader)
                            ForEach(phrases.filter { $0.scene == scene }) { phrase in
                                card(phrase)
                            }
                        }
                    } else {
                        ForEach(visible) { phrase in
                            card(phrase)
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
        .elderlyScreen(title: category.displayName)
        .task { await load() }
    }

    private func card(_ phrase: Phrase) -> some View {
        JapanesePhraseCard(phrase: phrase) {
            router.showToStaff(StaffDisplayContent(phrase: phrase))
        }
    }

    private func load() async {
        do {
            phrases = try await dependencies.phrases.phrases(in: category)
            error = nil
            // 預設選第一個場面（長輩通常只需要當下那個情境）
            if selectedScene == Self.allScenes, let first = scenes.first, scenes.count > 1 {
                selectedScene = first
            }
        } catch {
            self.error = UserFacingError.from(error)
        }
    }
}

#Preview {
    NavigationStack {
        PhraseListView(category: .hotel)
    }
    .environment(AppRouter())
    .environment(\.dependencies, .preview)
}
