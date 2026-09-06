import SwiftUI

/// 尚未完成的功能頁：明確告訴使用者「還沒有」，並且有返回。
struct ComingSoonView: View {
    let title: String
    let message: String
    var systemImage: String = AppIcon.comingSoon

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: systemImage)
                .font(.system(size: 56))
                .foregroundStyle(AppColors.secondaryText)
                .accessibilityHidden(true)
            Text("這個功能還在準備中")
                .font(.app(.sectionTitle))
                .foregroundStyle(AppColors.primaryText)
            Text(message)
                .font(.app(.body))
                .foregroundStyle(AppColors.secondaryText)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(AccessibilityMetrics.screenPadding)
        .elderlyScreen(title: title)
    }
}

#Preview {
    NavigationStack {
        ComingSoonView(title: "拍菜單", message: "下一個版本就可以拍菜單、自動整理成清單。")
    }
}
