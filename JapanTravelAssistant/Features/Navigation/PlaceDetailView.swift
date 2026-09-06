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
                    Label(place.category.displayName, systemImage: place.category.systemImage)
                        .font(.app(.caption))
                        .foregroundStyle(PlacesView.tint(for: place.category))
                    Text(place.address ?? "（沒有地址）")
                        .font(.app(.body))
                        .foregroundStyle(AppColors.primaryText)
                        .textSelection(.enabled)
                    if let note = place.note?.nilIfBlank {
                        Text(note)
                            .font(.app(.caption))
                            .foregroundStyle(AppColors.secondaryText)
                    }
                }
                .padding(AccessibilityMetrics.screenPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: AccessibilityMetrics.cornerRadius, style: .continuous))

                PrimaryButton(title: isOpening ? "打開地圖中…" : "帶我去（\(settings.navigationProvider.displayName)）", systemImage: AppIcon.go, isLoading: isOpening, isEnabled: place.canNavigate) {
                    Task { await navigate(place) }
                }

                SecondaryButton(title: "地址給司機看", systemImage: AppIcon.showToStaff, isEnabled: place.address?.nilIfBlank != nil) {
                    router.showToStaff(StaffDisplayContent(
                        japanese: "ここまでお願いします。\n\(place.name)\n\(place.address ?? "")",
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
                        router.push(.placeEditor(place.id))
                    }
                    Button(role: .destructive) { confirmDelete = true } label: {
                        Label("刪除", systemImage: AppIcon.delete)
                            .font(.app(.buttonLabel))
                            .foregroundStyle(AppColors.error)
                            .elderlyTapTarget()
                    }
                    .confirmationDialog("確定要刪除「\(place.name)」嗎？", isPresented: $confirmDelete, titleVisibility: .visible) {
                        Button("刪除", role: .destructive) {
                            store.remove(id: place.id)
                            router.popOrPush(.places)
                        }
                        Button("不要刪除", role: .cancel) {}
                    }
                }
                .padding(.top, 8)
            }
            .padding(AccessibilityMetrics.screenPadding)
        }
    }

    private func navigate(_ place: Place) async {
        isOpening = true
        defer { isOpening = false }
        do {
            try await dependencies.navigation.open(place, using: settings.navigationProvider)
            store.markUsed(id: place.id)
            error = nil
        } catch {
            self.error = UserFacingError.from(error)
        }
    }
}

#Preview {
    let store = PlaceStore(directory: nil)
    let place = Place(name: "東京ステーションホテル", address: "〒100-0005 東京都千代田区丸の内1丁目9-1", latitude: 35.68, longitude: 139.76, category: .hotel, phone: "+81-3-5220-1111", note: "退房 11:00")
    store.add(place)
    return NavigationStack { PlaceDetailView(placeId: place.id) }
        .environment(AppRouter())
        .environment(store)
        .environment(SettingsStore(defaults: UserDefaults(suiteName: "preview")!))
        .environment(\.dependencies, .preview)
}
