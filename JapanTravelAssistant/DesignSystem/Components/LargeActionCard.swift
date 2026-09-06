import SwiftUI

/// 首頁與各功能入口用的大卡片：Icon + 中文標題 + 一句說明。整張都可以按。
struct LargeActionCard: View {
    let title: String
    let subtitle: String?
    let systemImage: String
    let tint: Color
    let action: () -> Void

    init(title: String, subtitle: String? = nil, systemImage: String, tint: Color = AppColors.accent, action: @escaping () -> Void) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.tint = tint
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            LargeActionCardLabel(title: title, subtitle: subtitle, systemImage: systemImage, tint: tint)
        }
        .buttonStyle(CardPressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityHint(subtitle ?? "")
        .accessibilityAddTraits(.isButton)
    }
}

/// 大卡片的外觀本體（不含 Button）。PhotosPicker 等需要自訂 label 的地方可以直接用。
struct LargeActionCardLabel: View {
    let title: String
    var subtitle: String? = nil
    let systemImage: String
    var tint: Color = AppColors.accent

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .title2) private var iconSize: CGFloat = 60

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) {
                    icon
                    texts
                }
            } else {
                HStack(spacing: 16) {
                    icon
                    texts
                    Spacer(minLength: 8)
                    Image(systemName: AppIcon.forward)
                        .font(.app(.body))
                        .foregroundStyle(AppColors.secondaryText)
                }
            }
        }
        .padding(AccessibilityMetrics.screenPadding)
        .frame(maxWidth: .infinity, minHeight: AccessibilityMetrics.largeCardMinHeight, alignment: .leading)
        .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: AccessibilityMetrics.cornerRadius, style: .continuous))
    }

    private var icon: some View {
        Image(systemName: systemImage)
            .font(.system(size: iconSize * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: iconSize, height: iconSize)
            .background(tint, in: RoundedRectangle(cornerRadius: iconSize * 0.28, style: .continuous))
    }

    private var texts: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.app(.cardTitle))
                .foregroundStyle(AppColors.primaryText)
                .multilineTextAlignment(.leading)
            if let subtitle {
                Text(subtitle)
                    .font(.app(.cardSubtitle))
                    .foregroundStyle(AppColors.secondaryText)
                    .multilineTextAlignment(.leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 按下時稍微縮小，讓長輩明確知道「有按到」。
struct CardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

#Preview("一般") {
    VStack(spacing: 16) {
        LargeActionCard(title: "我要跟人說話", subtitle: "飯店、餐廳、購物常用的話", systemImage: AppIcon.talk, tint: AppColors.talk) {}
        LargeActionCard(title: "我遇到問題", systemImage: AppIcon.help, tint: AppColors.help) {}
    }
    .padding()
    .background(AppColors.screenBackground)
}

#Preview("超大字體") {
    LargeActionCard(title: "我要看懂這個", subtitle: "菜單、商品、價牌", systemImage: AppIcon.understand, tint: AppColors.understand) {}
        .padding()
        .background(AppColors.screenBackground)
        .dynamicTypeSize(.accessibility3)
}
