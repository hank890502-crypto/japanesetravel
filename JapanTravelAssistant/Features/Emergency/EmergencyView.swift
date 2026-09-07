import SwiftUI
import UIKit

/// 「我遇到問題」：最上面是打電話，下面是依場面分類的緊急句子。
struct EmergencyView: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.dependencies) private var dependencies
    @State private var phrases: [Phrase] = []
    @State private var selectedScene = EmergencyView.allScenes
    /// 只有第一次載入才預選場面（從「給店員看」回來不要把「全部」跳掉）
    @State private var didPickInitialScene = false
    /// iPad 等沒有電話功能的裝置：卡片改成顯示大字號碼，不要按了沒反應
    @State private var canCall = true

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
                    if canCall {
                        LargeActionCard(title: number.title, subtitle: number.subtitle, systemImage: AppIcon.phone, tint: AppColors.help) {
                            call(number.id)
                        }
                    } else {
                        cannotCallCard(number)
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
        .onAppear { canCall = Self.deviceCanCall() }
        .task {
            phrases = (try? await dependencies.phrases.phrases(in: .emergency)) ?? []
            if !didPickInitialScene {
                didPickInitialScene = true
                if let first = scenes.first, scenes.count > 1 { selectedScene = first }
            }
        }
    }

    /// 不能打電話時的卡片：大字號碼可以直接拿給旁人看，並說清楚要用手機撥。
    private func cannotCallCard(_ number: EmergencyNumber) -> some View {
        HStack(alignment: .center, spacing: 16) {
            Text(number.id)
                .font(.system(.largeTitle, design: .rounded, weight: .heavy))
                .foregroundStyle(AppColors.help)
                .padding(.horizontal, 12)
                .frame(minWidth: AccessibilityMetrics.minimumTapTarget, minHeight: AccessibilityMetrics.minimumTapTarget)
                .background(AppColors.help.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(number.subtitle)
                    .font(.app(.cardTitle))
                    .foregroundStyle(AppColors.primaryText)
                Text("這台裝置不能打電話，請用手機撥 \(number.id)。")
                    .font(.app(.cardSubtitle))
                    .foregroundStyle(AppColors.secondaryText)
            }
            Spacer(minLength: 0)
        }
        .padding(AccessibilityMetrics.screenPadding)
        .frame(maxWidth: .infinity, minHeight: AccessibilityMetrics.largeCardMinHeight, alignment: .leading)
        .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: AccessibilityMetrics.cornerRadius, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(number.subtitle)，電話 \(number.id)。這台裝置不能打電話，請用手機撥。")
    }

    /// 這台裝置能不能撥電話（iPad、沒有通話功能的裝置會是 false）
    private static func deviceCanCall() -> Bool {
        guard let url = URL(string: "tel://119") else { return false }
        return UIApplication.shared.canOpenURL(url)
    }

    private func call(_ number: String) {
        guard let url = URL(string: "tel://\(number)") else { return }
        UIApplication.shared.open(url) { opened in
            // 真的打不開就改成顯示號碼，不要無聲失敗
            if !opened { canCall = false }
        }
    }
}

#Preview {
    NavigationStack { EmergencyView() }
        .environment(AppRouter())
        .environment(\.dependencies, .preview)
}
