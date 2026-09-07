import SwiftUI

/// 一趟旅程：時間表（按天）、會去的地點（不重複）、推薦景點，以及地圖。
struct TripPlacesView: View {
    let tripId: UUID

    @Environment(AppRouter.self) private var router
    @Environment(PlaceStore.self) private var store
    @Environment(\.dependencies) private var dependencies

    @State private var section = "timeline"
    @State private var isGeocoding = false

    private var trip: Trip? { store.trip(id: tripId) }

    var body: some View {
        let groups = store.dayGroups(in: tripId)
        let unique = store.uniquePlaces(in: tripId)
        let recommendations = store.recommendations(in: tripId)
        let isEmpty = groups.isEmpty && unique.isEmpty && recommendations.isEmpty

        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 16, pinnedViews: [.sectionHeaders]) {
                if let range = trip?.dateRangeText {
                    Text(range)
                        .font(.app(.body))
                        .foregroundStyle(AppColors.secondaryText)
                }

                HStack(spacing: 12) {
                    SecondaryButton(title: "新增地點", systemImage: AppIcon.add) { router.push(.placeSearch(tripId: tripId)) }
                    SecondaryButton(title: "修改旅程", systemImage: AppIcon.edit) { router.push(.tripEditor(tripId)) }
                }

                if !isEmpty, let package = store.package(for: tripId) {
                    ShareLink(item: package, preview: SharePreview(package.trip.name, image: Image(systemName: "suitcase.fill"))) {
                        LargeActionCardLabel(title: "分享這趟旅程給家人", subtitle: "用 AirDrop 或 LINE 傳過去，對方點開就有一樣的行程", systemImage: "square.and.arrow.up", tint: AppColors.talk)
                    }
                    .buttonStyle(CardPressStyle())
                    .accessibilityLabel("分享這趟旅程給家人")
                }

                if isEmpty {
                    LargeActionCard(title: "用 ChatGPT 一次匯入整趟行程", subtitle: "把討論行程的對話整理成地點清單", systemImage: AppIcon.sparkles, tint: AppColors.go) {
                        router.push(.tripImport(tripId))
                    }
                    Text("這趟還沒有地點。可以搜尋、自己輸入，或用 ChatGPT 一次匯入。")
                        .font(.app(.body))
                        .foregroundStyle(AppColors.secondaryText)
                } else {
                    LargeActionCard(title: "看地圖", subtitle: "我在哪裡？附近有哪些這趟要去的地方", systemImage: AppIcon.go, tint: AppColors.go) {
                        router.push(.tripMap(tripId))
                    }

                    Section {
                        switch section {
                        case "places":
                            Text("這趟總共會去 \(unique.count) 個地方（同一個地方只列一次）。")
                                .font(.app(.body))
                                .foregroundStyle(AppColors.secondaryText)
                            ForEach(unique) { place in placeCard(place) }
                        case "recommend":
                            if recommendations.isEmpty {
                                Text("還沒有推薦景點。用 ChatGPT 匯入行程時會一起帶進來。")
                                    .font(.app(.body))
                                    .foregroundStyle(AppColors.secondaryText)
                            } else {
                                Text("行程裡沒有、但附近值得順路去的地方。點進去可以加到行程。")
                                    .font(.app(.body))
                                    .foregroundStyle(AppColors.secondaryText)
                                ForEach(recommendations) { place in placeCard(place, subtitle: place.recommendationReason) }
                            }
                        default:
                            if isGeocoding {
                                Label("正在幫地點找座標…", systemImage: "location.fill")
                                    .font(.app(.caption))
                                    .foregroundStyle(AppColors.secondaryText)
                            }
                            ForEach(groups) { group in
                                if group.label != nil || groups.count > 1 {
                                    Text(group.label ?? "還沒排進哪一天")
                                        .font(.app(.sectionTitle))
                                        .padding(.top, 8)
                                        .accessibilityAddTraits(.isHeader)
                                }
                                ForEach(group.entries) { entry in placeCard(entry.place) }
                            }
                        }

                        LargeActionCard(title: "用 ChatGPT 匯入或補充行程", subtitle: "會自動合併同名地點，並帶入推薦景點", systemImage: AppIcon.sparkles, tint: AppColors.go) {
                            router.push(.tripImport(tripId))
                        }
                        .padding(.top, 8)
                    } header: {
                        CategoryChipBar(chips: [
                            .init(id: "timeline", title: "時間表"),
                            .init(id: "places", title: "會去的地點", badge: unique.count),
                            .init(id: "recommend", title: "推薦景點", badge: recommendations.count),
                        ], selectedId: $section)
                        .padding(.horizontal, -AccessibilityMetrics.screenPadding)
                    }
                }
            }
            .padding(.horizontal, AccessibilityMetrics.screenPadding)
            .padding(.bottom, AccessibilityMetrics.screenPadding)
        }
        .elderlyScreen(title: trip?.name ?? "旅程")
        .task(id: tripId) {
            await geocodeMissing()
        }
    }

    private func placeCard(_ place: Place, subtitle: String? = nil) -> some View {
        LargeActionCard(
            title: place.name,
            subtitle: subtitle ?? [place.japaneseName, place.address].compactMap { $0?.nilIfBlank }.first ?? place.category.displayName,
            systemImage: place.category.systemImage,
            tint: PlaceTint.color(for: place.category)
        ) {
            router.push(.placeDetail(place.id))
        }
    }

    /// 沒座標的地點在背景補座標（地圖與 Google／Yahoo 導航需要）。
    /// 一次把清單跑完：查過（不論成功失敗）就記在 store 裡，這次 App 開著期間不再重試；
    /// 每次查詢間隔至少 1 秒，避免一次太多請求被限流，之後連查得到的也失敗。
    private func geocodeMissing() async {
        let pending = store.placesNeedingGeocode(in: tripId)
        guard !pending.isEmpty else { return }
        isGeocoding = true
        defer { isGeocoding = false }
        for (index, place) in pending.enumerated() {
            if index > 0 {
                try? await Task.sleep(for: .seconds(1))
            }
            if Task.isCancelled { return }
            let result = await dependencies.geocoder.coordinate(address: place.address, name: place.japaneseName ?? place.name)
            store.markGeocodeAttempted(place.id)
            if let result {
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
