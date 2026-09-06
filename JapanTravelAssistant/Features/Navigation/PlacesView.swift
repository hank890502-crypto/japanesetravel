import SwiftUI

/// 「我要去一個地方」：M0 先用一個示範地點驗證 Apple 地圖可以開啟。
struct PlacesView: View {
    @Environment(\.dependencies) private var dependencies
    @Environment(SettingsStore.self) private var settings
    @State private var error: UserFacingError?

    private let demoPlace = Place(name: "東京駅", address: "東京都千代田区丸の内1丁目", latitude: 35.681236, longitude: 139.767125)

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let error {
                    ErrorBanner(error: error) { self.error = nil }
                }
                Text("點一下地點，就會打開地圖帶你去。")
                    .font(.app(.body))
                    .foregroundStyle(AppColors.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                LargeActionCard(
                    title: demoPlace.name,
                    subtitle: demoPlace.address,
                    systemImage: AppIcon.go,
                    tint: AppColors.go
                ) {
                    Task { await open(demoPlace) }
                }
                Text("目前用「\(settings.navigationProvider.displayName)」帶路，可以在設定裡更換。儲存自己的地點會在之後的版本加入。")
                    .font(.app(.caption))
                    .foregroundStyle(AppColors.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)
            }
            .padding(AccessibilityMetrics.screenPadding)
        }
        .elderlyScreen(title: "我要去一個地方")
    }

    @MainActor
    private func open(_ place: Place) async {
        do {
            try await dependencies.navigation.open(place, using: settings.navigationProvider)
        } catch {
            self.error = UserFacingError.from(error)
        }
    }
}

#Preview {
    NavigationStack { PlacesView() }
        .environment(SettingsStore(defaults: UserDefaults(suiteName: "preview")!))
        .environment(\.dependencies, .preview)
}
