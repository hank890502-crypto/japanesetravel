import CoreLocation
import MapKit
import SwiftUI

/// 這趟旅程的地圖：我在哪裡、要去的地方（藍）、推薦的地方（綠）。點一個大頭針看名稱，再按「看這個地點」。
struct TripMapView: View {
    let tripId: UUID

    @Environment(AppRouter.self) private var router
    @Environment(PlaceStore.self) private var store
    @Environment(\.dependencies) private var dependencies

    @State private var position: MapCameraPosition = .automatic
    @State private var selectedId: UUID?
    @State private var showRecommendations = true

    private var itinerary: [Place] { store.uniquePlaces(in: tripId).filter(\.hasCoordinate) }
    private var recommendations: [Place] { store.recommendations(in: tripId).filter(\.hasCoordinate) }
    private var shown: [Place] { itinerary + (showRecommendations ? recommendations : []) }
    private var selected: Place? { selectedId.flatMap { store.place(id: $0) } }
    private var missingCount: Int { store.places(in: tripId).filter { !$0.hasCoordinate }.count }

    var body: some View {
        VStack(spacing: 0) {
            Map(position: $position, selection: $selectedId) {
                UserAnnotation()
                ForEach(shown) { place in
                    Annotation(place.name, coordinate: CLLocationCoordinate2D(latitude: place.latitude ?? 0, longitude: place.longitude ?? 0)) {
                        pin(for: place)
                    }
                    .tag(place.id)
                }
            }
            .mapControls {
                MapUserLocationButton()
                MapCompass()
            }
            .mapStyle(.standard(pointsOfInterest: .including([.publicTransport, .restaurant, .hotel, .store, .pharmacy, .hospital])))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .top) {
                legend
            }

            bottomPanel
        }
        .elderlyScreen(title: "地圖")
        .task {
            _ = await dependencies.location.currentLocation()   // 觸發定位權限，讓「我在哪裡」顯示
            fitAll()
        }
    }

    // MARK: - 區塊

    private func pin(for place: Place) -> some View {
        let isSelected = place.id == selectedId
        return VStack(spacing: 2) {
            Image(systemName: place.category.systemImage)
                .font(.system(size: isSelected ? 20 : 15, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: isSelected ? 44 : 34, height: isSelected ? 44 : 34)
                .background(place.isRecommendation ? AppColors.success : AppColors.accent, in: Circle())
                .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                .shadow(radius: 2)
            // 地圖本身的顏色不跟 App 的深淺色走，所以地名膠囊固定「白底黑字」，深色模式也看得到
            Text(place.name)
                .font(.system(.caption, weight: .bold))
                .foregroundStyle(.black)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.white.opacity(0.92), in: Capsule())
                .shadow(color: .black.opacity(0.25), radius: 1.5, y: 1)
                .lineLimit(1)
        }
        .accessibilityLabel("\(place.isRecommendation ? "推薦：" : "")\(place.name)")
    }

    /// 地圖上方的圖例。兩個按鈕浮在地圖上、手勢容易被地圖搶走，所以點擊區至少 44pt 高、文字用 body。
    private var legend: some View {
        HStack(spacing: 6) {
            Label("要去的", systemImage: "circle.fill")
                .foregroundStyle(AppColors.accent)
                .padding(.horizontal, 8)
            Button {
                withAnimation { showRecommendations.toggle() }
            } label: {
                Label("推薦", systemImage: showRecommendations ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(AppColors.success)
                    .legendTapTarget()
            }
            .accessibilityLabel(showRecommendations ? "隱藏推薦景點" : "顯示推薦景點")
            .accessibilityAddTraits(showRecommendations ? [.isButton, .isSelected] : .isButton)
            Spacer(minLength: 0)
            Button {
                fitAll()
            } label: {
                Label("看全部", systemImage: "arrow.up.left.and.arrow.down.right")
                    .foregroundStyle(AppColors.accent)
                    .legendTapTarget()
            }
            .accessibilityLabel("看全部地點")
        }
        .font(.system(.body, weight: .semibold))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(12)
    }

    private var bottomPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let selected {
                HStack(spacing: 12) {
                    Image(systemName: selected.category.systemImage)
                        .font(.app(.cardTitle))
                        .foregroundStyle(selected.isRecommendation ? AppColors.success : AppColors.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(selected.name).font(.app(.cardTitle))
                        Text(selected.isRecommendation ? (selected.recommendationReason ?? "推薦景點") : (selected.address ?? selected.category.displayName))
                            .font(.app(.caption))
                            .foregroundStyle(AppColors.secondaryText)
                            .lineLimit(2)
                    }
                    Spacer()
                }
                PrimaryButton(title: "看這個地點（帶我去、給司機看）", systemImage: AppIcon.forward) {
                    router.push(.placeDetail(selected.id))
                }
            } else {
                Text(shown.isEmpty
                     ? "地點還沒有座標，請稍等 App 補上，或到地點頁修改地址。"
                     : "藍色是這趟要去的地方，綠色是推薦。點一個大頭針看詳細。\(missingCount > 0 ? "另有 \(missingCount) 個地點還在找座標。" : "")")
                    .font(.app(.body))
                    .foregroundStyle(AppColors.secondaryText)
            }
        }
        .padding(AccessibilityMetrics.screenPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.cardBackground)
    }

    private func fitAll() {
        let coords = shown.compactMap { place -> CLLocationCoordinate2D? in
            guard let lat = place.latitude, let lon = place.longitude else { return nil }
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
        guard !coords.isEmpty else { return }
        let lats = coords.map(\.latitude), lons = coords.map(\.longitude)
        let center = CLLocationCoordinate2D(latitude: (lats.min()! + lats.max()!) / 2, longitude: (lons.min()! + lons.max()!) / 2)
        let span = MKCoordinateSpan(latitudeDelta: max((lats.max()! - lats.min()!) * 1.5, 0.02), longitudeDelta: max((lons.max()! - lons.min()!) * 1.5, 0.02))
        withAnimation { position = .region(MKCoordinateRegion(center: center, span: span)) }
    }
}

private extension View {
    /// 圖例按鈕的可點區：至少 44pt 高、左右留白，整塊都能按。
    func legendTapTarget() -> some View {
        padding(.horizontal, 10)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
    }
}

#Preview {
    let store = PlaceStore(directory: nil)
    let trip = store.addTrip(name: "9 月名古屋")
    store.add(Place(name: "名古屋城", latitude: 35.1856, longitude: 136.8998, category: .sight), to: trip.id)
    store.add(Place(name: "名古屋駅", latitude: 35.1709, longitude: 136.8815, category: .station), to: trip.id)
    store.add(Place(name: "大須商店街", latitude: 35.159, longitude: 136.903, category: .shopping, isRecommendation: true, recommendationReason: "好逛、好吃"), to: trip.id)
    return NavigationStack { TripMapView(tripId: trip.id) }
        .environment(AppRouter())
        .environment(store)
        .environment(\.dependencies, .preview)
}
