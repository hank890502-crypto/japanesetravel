import SwiftUI

/// 收到家人分享的旅程檔：確認後匯入。
struct TripReceiveView: View {
    let package: TripPackage

    @Environment(AppRouter.self) private var router
    @Environment(PlaceStore.self) private var store

    private var alreadyHave: Bool { store.trip(id: package.trip.id) != nil }
    private var itineraryCount: Int { package.places.filter { !$0.isRecommendation }.count }
    private var recommendationCount: Int { package.places.filter(\.isRecommendation).count }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Button("取消") { router.receivedTrip = nil }
                    .font(.app(.buttonLabel))
                    .frame(minHeight: AccessibilityMetrics.minimumTapTarget)
                Spacer()
            }
            Text("收到一趟旅程")
                .font(.app(.screenTitle))
            VStack(alignment: .leading, spacing: 8) {
                Text(package.trip.name)
                    .font(.app(.cardTitle))
                if let range = package.trip.dateRangeText {
                    Text(range).font(.app(.body)).foregroundStyle(AppColors.secondaryText)
                }
                Text("時間表 \(package.stops.count) 站、\(itineraryCount) 個地點、\(recommendationCount) 個推薦景點")
                    .font(.app(.body))
                    .foregroundStyle(AppColors.secondaryText)
            }
            .padding(AccessibilityMetrics.screenPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: AccessibilityMetrics.cornerRadius, style: .continuous))

            if alreadyHave {
                Text("你已經有這趟旅程了。匯入會用收到的內容更新它（你自己加的地點會被覆蓋）。")
                    .font(.app(.body))
                    .foregroundStyle(AppColors.secondaryText)
            }

            PrimaryButton(title: alreadyHave ? "更新我的這趟旅程" : "加到我的旅程", systemImage: AppIcon.check) {
                let trip = store.importPackage(package)
                router.receivedTrip = nil
                router.path = [.places, .tripPlaces(trip.id)]
            }
            Spacer()
        }
        .padding(AccessibilityMetrics.screenPadding)
        .background(AppColors.screenBackground.ignoresSafeArea())
    }
}

#Preview {
    let store = PlaceStore(directory: nil)
    let trip = store.addTrip(name: "9 月名古屋")
    store.add(Place(name: "名古屋城", category: .sight), to: trip.id)
    return TripReceiveView(package: store.package(for: trip.id)!)
        .environment(AppRouter())
        .environment(store)
}
