import SwiftUI

/// 大卡片單選列：左邊勾勾、可選 icon、標題、副標。整張可以按。
/// 設定頁（AI 幫手、地圖）與菜單分類選單共用，取代系統的小字選單。
struct ChoiceCard: View {
    let title: String
    var subtitle: String? = nil
    var systemImage: String? = nil
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(.title2, weight: .semibold))
                    .foregroundStyle(isSelected ? AppColors.accent : AppColors.secondaryText)
                    .padding(.top, 2)
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.app(.cardTitle))
                        .foregroundStyle(AppColors.accent)
                        .padding(.top, 2)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.app(.cardTitle))
                        .foregroundStyle(AppColors.primaryText)
                        .multilineTextAlignment(.leading)
                    if let subtitle = subtitle?.nilIfBlank {
                        Text(subtitle)
                            .font(.app(.caption))
                            .foregroundStyle(AppColors.secondaryText)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(AccessibilityMetrics.screenPadding)
            .frame(maxWidth: .infinity, minHeight: AccessibilityMetrics.minimumTapTarget, alignment: .leading)
            .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: AccessibilityMetrics.cornerRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: AccessibilityMetrics.cornerRadius, style: .continuous).strokeBorder(isSelected ? AppColors.accent : .clear, lineWidth: 2))
        }
        .buttonStyle(CardPressStyle())
        .accessibilityLabel(title)
        .accessibilityHint(subtitle ?? "")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

#Preview {
    VStack(spacing: 12) {
        ChoiceCard(title: "揚げ物", subtitle: "炸物", isSelected: true) {}
        ChoiceCard(title: "ドリンク", subtitle: "飲料", isSelected: false) {}
        ChoiceCard(title: "Apple 地圖", systemImage: "map.fill", isSelected: false) {}
    }
    .padding()
    .background(AppColors.screenBackground)
}
