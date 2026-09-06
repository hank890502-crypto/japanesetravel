import SwiftUI

/// 菜單品項卡片：日文名稱、中文（可能沒有）、價格。右側可放「修改」或「+ / -」。
struct MenuItemCard<Trailing: View>: View {
    let japaneseName: String
    let chineseName: String?
    var reading: String? = nil
    let price: Decimal?
    var currency: String = "JPY"
    var note: String? = nil
    /// 選項摘要，例如「大份 +¥150、定食 +¥300」
    var optionsSummary: String? = nil
    var isLowConfidence: Bool = false
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(japaneseName.nilIfBlank ?? "（沒有名稱）")
                    .font(.app(.japanese))
                    .foregroundStyle(AppColors.primaryText)
                    .multilineTextAlignment(.leading)
                if let reading = reading?.nilIfBlank {
                    Text(reading)
                        .font(.system(.subheadline, design: .rounded).italic())
                        .foregroundStyle(AppColors.secondaryText)
                        .accessibilityLabel("讀音 \(reading)")
                }
                if let chineseName = chineseName?.nilIfBlank {
                    Text(chineseName)
                        .font(.app(.body))
                        .foregroundStyle(AppColors.secondaryText)
                } else {
                    Text("還沒有中文")
                        .font(.app(.caption))
                        .foregroundStyle(AppColors.secondaryText)
                }
                if let note = note?.nilIfBlank {
                    Text(note)
                        .font(.app(.caption))
                        .foregroundStyle(AppColors.secondaryText)
                }
                if let optionsSummary = optionsSummary?.nilIfBlank {
                    Label(optionsSummary, systemImage: "slider.horizontal.3")
                        .font(.app(.caption))
                        .foregroundStyle(AppColors.accent)
                }
                HStack(spacing: 8) {
                    Text(PriceFormatter.string(price, currency: currency) ?? "沒有價格")
                        .font(.app(.body).weight(.semibold))
                        .foregroundStyle(price == nil ? AppColors.secondaryText : AppColors.primaryText)
                    if isLowConfidence {
                        Label("請確認", systemImage: AppIcon.warning)
                            .font(.system(.caption, weight: .semibold))
                            .foregroundStyle(AppColors.error)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            trailing()
        }
        .padding(AccessibilityMetrics.screenPadding)
        .frame(maxWidth: .infinity, minHeight: AccessibilityMetrics.largeCardMinHeight, alignment: .leading)
        .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: AccessibilityMetrics.cornerRadius, style: .continuous))
    }
}

#Preview {
    VStack(spacing: 16) {
        MenuItemCard(japaneseName: "とんかつ", chineseName: "炸豬排", reading: "tonkatsu", price: 540, optionsSummary: "大份 +¥150、定食 +¥300") {
            Image(systemName: AppIcon.edit).font(.app(.cardTitle)).foregroundStyle(AppColors.accent)
        }
        MenuItemCard(japaneseName: "手羽先", chineseName: nil, price: nil, isLowConfidence: true) {
            Image(systemName: AppIcon.edit).font(.app(.cardTitle)).foregroundStyle(AppColors.accent)
        }
    }
    .padding()
    .background(AppColors.screenBackground)
}
