import SwiftUI

/// 「我要看懂這個」：選擇要看懂什麼。
struct UnderstandHubView: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                LargeActionCard(
                    title: "看菜單、一起點餐",
                    subtitle: "拍下菜單，全家一起點",
                    systemImage: AppIcon.restaurant,
                    tint: AppColors.understand
                ) {
                    router.push(.restaurantHub)
                }
                LargeActionCard(
                    title: "找商品",
                    subtitle: "用手機裡的照片問店員",
                    systemImage: AppIcon.shopping,
                    tint: AppColors.understand
                ) {
                    router.push(.shoppingFindProduct)
                }
            }
            .padding(AccessibilityMetrics.screenPadding)
        }
        .elderlyScreen(title: "我要看懂這個")
    }
}

#Preview {
    NavigationStack {
        UnderstandHubView()
    }
    .environment(AppRouter())
    .environment(\.dependencies, .preview)
}
