import SwiftUI

/// 一句常用日文的卡片：中文大字在上、日文在下，整張可按 → 給店員看。
struct JapanesePhraseCard: View {
    let phrase: Phrase
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(phrase.chinese)
                        .font(.app(.cardTitle))
                        .foregroundStyle(AppColors.primaryText)
                        .multilineTextAlignment(.leading)
                    Text(phrase.japanese)
                        .font(.app(.japanese))
                        .foregroundStyle(AppColors.secondaryText)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(spacing: 4) {
                    Image(systemName: AppIcon.showToStaff)
                        .font(.system(.title2, weight: .semibold))
                    Text("給對方看")
                        .font(.system(.caption, weight: .semibold))
                }
                .foregroundStyle(AppColors.accent)
                .frame(minWidth: 64)
            }
            .padding(AccessibilityMetrics.screenPadding)
            .frame(maxWidth: .infinity, minHeight: AccessibilityMetrics.largeCardMinHeight, alignment: .leading)
            .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: AccessibilityMetrics.cornerRadius, style: .continuous))
        }
        .buttonStyle(CardPressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(phrase.chinese)，日文 \(phrase.japanese)")
        .accessibilityHint("用大字顯示日文給對方看")
        .accessibilityAddTraits(.isButton)
    }
}

#Preview {
    VStack(spacing: 16) {
        JapanesePhraseCard(phrase: Phrase(id: "1", category: .shopping, chinese: "請問有這個商品嗎？", japanese: "こちらの商品はありますか？", reading: nil)) {}
        JapanesePhraseCard(phrase: Phrase(id: "2", category: .hotel, chinese: "房間有問題，可以來看一下嗎？", japanese: "部屋に問題があります。見に来てもらえますか？", reading: nil)) {}
    }
    .padding()
    .background(AppColors.screenBackground)
}
