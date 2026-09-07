import SwiftUI

/// 一趟旅程裡的地點，按天分組。新增方式：搜尋、自己輸入、用 ChatGPT 一次匯入。
struct TripPlacesView: View {
    let tripId: UUID

    @Environment(AppRouter.self) private var router
    @Environment(PlaceStore.self) private var store
    @Environment(\.dependencies) private var dependencies

    @State private var isGeocoding = false

    private var trip: Trip? { store.trip(id: tripId) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let range = trip?.dateRangeText {
                    Text(range)
                        .font(.app(.body))
                        .foregroundStyle(AppColors.secondaryText)
                }

                HStack(spacing: 12) {
                    SecondaryButton(title: "新增地點", systemImage: AppIcon.add) { router.push(.placeSearch(tripId: tripId)) }
                    SecondaryButton(title: "修改旅程", systemImage: AppIcon.edit) { router.push(.tripEditor(tripId)) }
                }

                LargeActionCard(title: "用 ChatGPT 一次匯入整趟行程", subtitle: "把討論行程的對話整理成地點清單", systemImage: AppIcon.sparkles, tint: AppColors.go) {
                    router.push(.tripImport(tripId))
                }

                let groups = store.dayGroups(in: tripId)
                if groups.isEmpty {
                    Text("這趟還沒有地點。可以搜尋、自己輸入，或用 ChatGPT 一次匯入。")
                        .font(.app(.body))
                        .foregroundStyle(AppColors.secondaryText)
                } else {
                    Text("點一下地點，可以帶路、把地址給司機看。")
                        .font(.app(.body))
                        .foregroundStyle(AppColors.secondaryText)
                    if isGeocoding {
                        Label("正在幫地點找座標…", systemImage: "location.fill")
                            .font(.app(.caption))
                            .foregroundStyle(AppColors.secondaryText)
                    }
                    ForEach(groups) { group in
                        if group.label != nil || groups.count > 1 {
                            Text(group.label ?? "其他")
                                .font(.app(.sectionTitle))
                                .padding(.top, 8)
                                .accessibilityAddTraits(.isHeader)
                        }
                        ForEach(group.places) { place in
                            LargeActionCard(
                                title: place.name,
                                subtitle: [place.japaneseName, place.address].compactMap { $0?.nilIfBlank }.first ?? place.category.displayName,
                                systemImage: place.category.systemImage,
                                tint: PlaceTint.color(for: place.category)
                            ) {
                                router.push(.placeDetail(place.id))
                            }
                        }
                    }
                }
            }
            .padding(AccessibilityMetrics.screenPadding)
        }
        .elderlyScreen(title: trip?.name ?? "旅程")
        .task(id: store.places(in: tripId).filter { !$0.hasCoordinate }.map(\.id)) {
            await geocodeMissing()
        }
    }

    /// 沒座標的地點在背景補座標（Google／Yahoo 導航需要）。
    private func geocodeMissing() async {
        let missing = store.places(in: tripId).filter { !$0.hasCoordinate && ($0.address?.nilIfBlank != nil || $0.japaneseName?.nilIfBlank != nil) }
        guard !missing.isEmpty else { return }
        isGeocoding = true
        defer { isGeocoding = false }
        for place in missing {
            if Task.isCancelled { return }
            if let result = await dependencies.geocoder.coordinate(address: place.address, name: place.japaneseName ?? place.name) {
                store.setCoordinate(placeId: place.id, latitude: result.latitude, longitude: result.longitude, address: result.address)
            }
        }
    }
}

#Preview {
    let store = PlaceStore(directory: nil)
    let trip = store.addTrip(name: "9 月名古屋")
    store.add(Place(name: "名古屋城", address: "愛知県名古屋市中区本丸1-1", category: .sight, japaneseName: "名古屋城", dayLabel: "第2天 9/13"), to: trip.id)
    return NavigationStack { TripPlacesView(tripId: trip.id) }
        .environment(AppRouter())
        .environment(store)
        .environment(\.dependencies, .preview)
}
