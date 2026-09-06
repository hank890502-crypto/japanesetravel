import SwiftUI

/// 使用者按到 AI 功能但尚未啟用時的提示（不是錯誤，是說明）。
struct AIUnavailableBanner: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: AppIcon.sparkles)
                    .font(.app(.cardTitle))
                    .foregroundStyle(AppColors.accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text("AI 分析目前尚未啟用")
                        .font(.app(.cardTitle))
                    Text("你仍然可以自己輸入或修改內容。要開啟 AI，請到「設定」選擇 AI 幫手。")
                        .font(.app(.body))
                        .foregroundStyle(AppColors.secondaryText)
                }
            }
            SecondaryButton(title: "前往設定", systemImage: "gearshape.fill") {
                router.push(.settings)
            }
        }
        .padding(AccessibilityMetrics.screenPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: AccessibilityMetrics.cornerRadius, style: .continuous))
    }
}
