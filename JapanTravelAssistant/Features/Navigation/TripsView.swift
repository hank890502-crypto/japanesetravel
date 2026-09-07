import SwiftUI

/// 「我要去一個地方」第一層：旅程列表。
struct TripsView: View {
    @Environment(AppRouter.self) private var router
    @Environment(PlaceStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text(store.trips.isEmpty
                     ? "先建立一趟旅程（例如 9 月名古屋），再把這趟會去的地點放進去。"
                     : "選一趟旅程，裡面有這趟會去的地點。")
                    .font(.app(.body))
                    .foregroundStyle(AppColors.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)

                LargeActionCard(title: "新增旅程", subtitle: "例如：9 月名古屋、12 月東京", systemImage: AppIcon.add, tint: AppColors.go) {
                    router.push(.tripEditor(nil))
                }

                ForEach(store.sortedTrips) { trip in
                    let count = store.places(in: trip.id).count
                    LargeActionCard(
                        title: trip.name,
                        subtitle: [trip.dateRangeText, count == 0 ? "還沒有地點" : "\(count) 個地點"].compactMap { $0 }.joined(separator: "・"),
                        systemImage: "suitcase.fill",
                        tint: AppColors.go
                    ) {
                        router.push(.tripPlaces(trip.id))
                    }
                }
            }
            .padding(AccessibilityMetrics.screenPadding)
        }
        .elderlyScreen(title: "我要去一個地方")
    }
}

/// 類型顏色（給各地點畫面共用）
enum PlaceTint {
    static func color(for category: PlaceCategory) -> Color {
        switch category {
        case .hotel: AppColors.talk
        case .station: AppColors.go
        case .restaurant: AppColors.understand
        case .shopping: Color(uiColor: .systemPurple)
        case .sight: Color(uiColor: .systemTeal)
        case .other: AppColors.secondaryText
        }
    }
}

#Preview {
    let store = PlaceStore(directory: nil)
    store.addTrip(name: "9 月名古屋", startDate: DayDate(year: 2026, month: 9, day: 12), endDate: DayDate(year: 2026, month: 9, day: 16))
    return NavigationStack { TripsView() }
        .environment(AppRouter())
        .environment(store)
}
