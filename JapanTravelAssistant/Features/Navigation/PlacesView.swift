import SwiftUI

/// 「我要去一個地方」：常去的地點列表。點一下進入地點頁（帶我去、給司機看）。
struct PlacesView: View {
    @Environment(AppRouter.self) private var router
    @Environment(PlaceStore.self) private var store
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if store.places.isEmpty {
                    Text("先把常去的地方存起來：飯店、車站、餐廳。之後點一下就能用地圖帶路，或把地址拿給司機看。")
                        .font(.app(.body))
                        .foregroundStyle(AppColors.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text("點一下地點，就會用「\(settings.navigationProvider.displayName)」帶你去。")
                        .font(.app(.body))
                        .foregroundStyle(AppColors.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                LargeActionCard(title: "新增地點", subtitle: "搜尋，或自己輸入地址", systemImage: AppIcon.add, tint: AppColors.go) {
                    router.push(.placeSearch)
                }

                ForEach(store.places) { place in
                    LargeActionCard(
                        title: place.name,
                        subtitle: place.address ?? place.category.displayName,
                        systemImage: place.category.systemImage,
                        tint: tint(for: place.category)
                    ) {
                        router.push(.placeDetail(place.id))
                    }
                }
            }
            .padding(AccessibilityMetrics.screenPadding)
        }
        .elderlyScreen(title: "我要去一個地方")
    }

    static func tint(for category: PlaceCategory) -> Color {
        switch category {
        case .hotel: AppColors.talk
        case .station: AppColors.go
        case .restaurant: AppColors.understand
        case .shopping: Color(uiColor: .systemPurple)
        case .sight: Color(uiColor: .systemTeal)
        case .other: AppColors.secondaryText
        }
    }

    private func tint(for category: PlaceCategory) -> Color { Self.tint(for: category) }
}

#Preview {
    let store = PlaceStore(directory: nil)
    store.add(Place(name: "東京駅", address: "〒100-0005 東京都千代田区丸の内1丁目", latitude: 35.68, longitude: 139.76, category: .station))
    return NavigationStack { PlacesView() }
        .environment(AppRouter())
        .environment(store)
        .environment(SettingsStore(defaults: UserDefaults(suiteName: "preview")!))
        .environment(\.dependencies, .preview)
}
