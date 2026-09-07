import SwiftUI
import UIKit

/// 一個地點：帶我去、地址給司機看、打電話、修改、刪除。
struct PlaceDetailView: View {
    let placeId: UUID

    @Environment(AppRouter.self) private var router
    @Environment(PlaceStore.self) private var store
    @Environment(SettingsStore.self) private var settings
    @Environment(\.dependencies) private var dependencies

    @State private var error: UserFacingError?
    @State private var isOpening = false
    @State private var confirmDelete = false
    @State private var showMapChooser = false

    private var place: Place? { store.place(id: placeId) }

    var body: some View {
        Group {
            if let place {
                content(place)
            } else {
                Text("這個地點已經被刪除了。")
                    .font(.app(.body))
                    .foregroundStyle(AppColors.secondaryText)
                    .padding()
            }
        }
        .elderlyScreen(title: place?.name ?? "地點")
    }

    private func content(_ place: Place) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let error {
                    ErrorBanner(error: error)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Label(([place.category.displayName] + (place.isRecommendation ? ["推薦景點"] : store.dayLabels(of: place.id))).joined(separator: "・"), systemImage: place.category.systemImage)
                        .font(.app(.caption))
                        .foregroundStyle(PlaceTint.color(for: place.category))
                    if let japanese = place.japaneseName?.nilIfBlank, japanese != place.name {
                        Text(japanese)
                            .font(.app(.japanese))
                            .foregroundStyle(AppColors.primaryText)
                    }
                    Text(place.address ?? "（沒有地址）")
                        .font(.app(.body))
                        .foregroundStyle(AppColors.primaryText)
                        .textSelection(.enabled)
                    if let note = place.note?.nilIfBlank {
                        Text(note)
                            .font(.app(.caption))
                            .foregroundStyle(AppColors.secondaryText)
                    }
                    if let reason = place.recommendationReason?.nilIfBlank {
                        Label(reason, systemImage: "hand.thumbsup.fill")
                            .font(.app(.caption))
                            .foregroundStyle(AppColors.success)
                    }
                }
                .padding(AccessibilityMetrics.screenPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: AccessibilityMetrics.cornerRadius, style: .continuous))

                PrimaryButton(title: isOpening ? "打開地圖中…" : "帶我去", systemImage: AppIcon.go, isLoading: isOpening, isEnabled: place.canNavigate) {
                    showMapChooser = true
                }
                .confirmationDialog("要用哪個地圖？", isPresented: $showMapChooser, titleVisibility: .visible) {
                    ForEach(orderedProviders, id: \.self) { provider in
                        Button(providerTitle(provider)) { Task { await navigate(place, using: provider) } }
                    }
                    Button("取消", role: .cancel) {}
                } message: {
                    Text(place.hasCoordinate ? "自駕建議用 Yahoo! カーナビ 或 Google 地圖；走路、搭車用 Apple 地圖也很方便。" : "這個地點還沒有座標，Apple 地圖會用地址找；其他地圖可能找不到。")
                }

                if place.isRecommendation {
                    SecondaryButton(title: "加到這趟行程", systemImage: AppIcon.add) {
                        store.addRecommendationToItinerary(placeId: place.id)
                    }
                }

                SecondaryButton(title: "地址給司機看", systemImage: AppIcon.showToStaff, isEnabled: place.address?.nilIfBlank != nil || place.japaneseName?.nilIfBlank != nil) {
                    router.showToStaff(StaffDisplayContent(
                        japanese: "ここまでお願いします。\n\(place.staffName)\n\(place.address ?? "")",
                        chinese: "請載我到這裡：\(place.name)"
                    ))
                }

                if let phone = place.phone?.nilIfBlank, let url = URL(string: "tel://\(phone.filter { !$0.isWhitespace })") {
                    SecondaryButton(title: "打電話 \(phone)", systemImage: AppIcon.phone) {
                        UIApplication.shared.open(url)
                    }
                }

                HStack(spacing: 12) {
                    SecondaryButton(title: "修改", systemImage: AppIcon.edit) {
                        router.push(.placeEditor(tripId: place.tripId ?? UUID(), placeId: place.id))
                    }
                    Button(role: .destructive) { confirmDelete = true } label: {
                        Label("刪除", systemImage: AppIcon.delete)
                            .font(.app(.buttonLabel))
                            .foregroundStyle(AppColors.error)
                            .elderlyTapTarget()
                    }
                    .confirmationDialog("確定要刪除「\(place.name)」嗎？", isPresented: $confirmDelete, titleVisibility: .visible) {
                        Button("刪除", role: .destructive) {
                            let tripId = place.tripId
                            store.remove(id: place.id)
                            if let tripId { router.popOrPush(.tripPlaces(tripId)) } else { router.popOrPush(.places) }
                        }
                        Button("不要刪除", role: .cancel) {}
                    }
                }
                .padding(.top, 8)
            }
            .padding(AccessibilityMetrics.screenPadding)
        }
    }

    /// 設定裡的預設地圖排第一，其餘照順序；沒裝的 Yahoo 也列出但會說明。
    private var orderedProviders: [NavigationProvider] {
        let preferred = settings.navigationProvider
        return [preferred] + NavigationProvider.allCases.filter { $0 != preferred }
    }

    private func providerTitle(_ provider: NavigationProvider) -> String {
        let installed = dependencies.navigation.isInstalled(provider)
        var title = provider.displayName
        if provider == settings.navigationProvider { title += "（預設）" }
        if !installed { title += provider == .googleMaps ? "（開網頁版）" : "（未安裝）" }
        return title
    }

    private func navigate(_ place: Place, using provider: NavigationProvider) async {
        isOpening = true
        defer { isOpening = false }
        do {
            try await dependencies.navigation.open(place, using: provider)
            error = nil
        } catch {
            self.error = UserFacingError.from(error)
        }
    }
}

#Preview {
    let store = PlaceStore(directory: nil)
    let trip = store.addTrip(name: "測試")
    let place = Place(name: "東京車站飯店", address: "〒100-0005 東京都千代田区丸の内1丁目9-1", latitude: 35.68, longitude: 139.76, category: .hotel, phone: "+81-3-5220-1111", note: "退房 11:00", japaneseName: "東京ステーションホテル")
    store.add(place, to: trip.id)
    return NavigationStack { PlaceDetailView(placeId: place.id) }
        .environment(AppRouter())
        .environment(store)
        .environment(SettingsStore(defaults: UserDefaults(suiteName: "preview")!))
        .environment(\.dependencies, .preview)
}
