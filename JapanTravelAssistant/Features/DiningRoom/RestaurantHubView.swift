import SwiftUI

/// 餐廳：兩個入口，一個給房主、一個給家人。
struct RestaurantHubView: View {
    @Environment(AppRouter.self) private var router
    @Environment(DiningSessionStore.self) private var sessionStore

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let session = sessionStore.current {
                    LargeActionCard(
                        title: "回到「\(session.room.name)」",
                        subtitle: "代碼 \(session.room.roomCode)，繼續點餐",
                        systemImage: AppIcon.joinRoom,
                        tint: AppColors.go
                    ) {
                        router.push(.room)
                    }
                }

                LargeActionCard(
                    title: "拍菜單、建立點餐",
                    subtitle: "我來拍菜單，讓大家一起點",
                    systemImage: AppIcon.camera,
                    tint: AppColors.understand
                ) {
                    router.push(.menuScan)
                }
                LargeActionCard(
                    title: "加入家人的點餐",
                    subtitle: "輸入家人給的代碼，或掃 QR Code",
                    systemImage: AppIcon.joinRoom,
                    tint: AppColors.talk
                ) {
                    router.push(.joinRoom(code: nil))
                }
            }
            .padding(AccessibilityMetrics.screenPadding)
        }
        .elderlyScreen(title: "餐廳")
    }
}

#Preview {
    NavigationStack {
        RestaurantHubView()
    }
    .environment(AppRouter())
    .environment(DiningSessionStore(defaults: UserDefaults(suiteName: "preview")!))
    .environment(\.dependencies, .preview)
}
