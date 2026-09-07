import SwiftUI

/// 自己輸入或修改地點：名稱、地址（日文）、類型、備註。存檔時如果沒有座標會用地址查一次。
struct PlaceEditorView: View {
    let tripId: UUID
    let placeId: UUID?

    @Environment(AppRouter.self) private var router
    @Environment(PlaceStore.self) private var store

    @State private var name = ""
    @State private var japaneseName = ""
    @State private var address = ""
    @State private var dayLabel = ""
    @State private var note = ""
    @State private var category: PlaceCategory = .other
    @State private var loaded = false
    @FocusState private var focused: Field?

    private enum Field { case name, japaneseName, address, dayLabel, note }
    private var isNew: Bool { placeId == nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                field(label: "名稱（你自己看得懂就好）", text: $name, placeholder: "例如：我們的飯店", focus: .name)
                field(label: "日文名稱（給司機看，可不填）", text: $japaneseName, placeholder: "例如：ドーミーイン名古屋", focus: .japaneseName)
                field(label: "日文地址（拿給司機看的）", text: $address, placeholder: "例如：東京都千代田区丸の内1丁目9-1", focus: .address)
                Text("地址可以從訂房確認信或 Google 地圖複製過來。")
                    .font(.app(.caption))
                    .foregroundStyle(AppColors.secondaryText)

                VStack(alignment: .leading, spacing: 8) {
                    Text("類型")
                        .font(.app(.body))
                        .foregroundStyle(AppColors.secondaryText)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(PlaceCategory.allCases) { kind in
                            Button {
                                category = kind
                            } label: {
                                VStack(spacing: 6) {
                                    Image(systemName: kind.systemImage)
                                        .font(.system(.title2, weight: .semibold))
                                    Text(kind.displayName)
                                        .font(.system(.subheadline, weight: .semibold))
                                }
                                .foregroundStyle(category == kind ? .white : AppColors.primaryText)
                                .frame(maxWidth: .infinity, minHeight: 72)
                                .background(category == kind ? PlaceTint.color(for: kind) : AppColors.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            }
                            .buttonStyle(CardPressStyle())
                            .accessibilityLabel(kind.displayName)
                            .accessibilityAddTraits(category == kind ? [.isButton, .isSelected] : .isButton)
                        }
                    }
                }

                field(label: "第幾天（可不填，例如 第1天 9/12）", text: $dayLabel, placeholder: "例如：第2天 9/13", focus: .dayLabel)
                field(label: "備註（可以不填）", text: $note, placeholder: "例如：退房 11:00、東口出來右轉", focus: .note)

                PrimaryButton(title: "儲存", systemImage: AppIcon.check, isEnabled: name.nilIfBlank != nil && address.nilIfBlank != nil) {
                    save()
                }
            }
            .padding(AccessibilityMetrics.screenPadding)
        }
        .scrollDismissesKeyboard(.interactively)
        .elderlyScreen(title: isNew ? "自己輸入地點" : "修改地點")
        .onAppear {
            guard !loaded else { return }
            loaded = true
            if let placeId, let place = store.place(id: placeId) {
                name = place.name
                japaneseName = place.japaneseName ?? ""
                address = place.address ?? ""
                dayLabel = store.dayLabels(of: place.id).first ?? ""
                note = place.note ?? ""
                category = place.category
            } else {
                focused = .name
            }
        }
    }

    private func field(label: String, text: Binding<String>, placeholder: String, focus: Field) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.app(.body))
                .foregroundStyle(AppColors.secondaryText)
            TextField(placeholder, text: text, axis: .vertical)
                .font(.app(.sectionTitle))
                .focused($focused, equals: focus)
                .padding(16)
                .frame(minHeight: AccessibilityMetrics.minimumTapTarget)
                .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(focused == focus ? AppColors.accent : AppColors.separator, lineWidth: 2))
        }
    }

    private func save() {
        focused = nil
        if let placeId, var place = store.place(id: placeId) {
            let addressChanged = place.address != address.nilIfBlank
            place.name = name.trimmingCharacters(in: .whitespaces)
            place.japaneseName = japaneseName.nilIfBlank
            place.address = address.nilIfBlank
            place.note = note.nilIfBlank
            place.category = category
            store.setDayLabel(dayLabel.nilIfBlank, for: place.id)
            if addressChanged {
                place.latitude = nil   // 地址改了，舊座標不算數；導航時會重新用地址查
                place.longitude = nil
            }
            store.update(place)
            router.popOrPush(.placeDetail(place.id))
        } else {
            let place = Place(name: name.trimmingCharacters(in: .whitespaces), address: address.nilIfBlank, category: category, note: note.nilIfBlank,
                              japaneseName: japaneseName.nilIfBlank, dayLabel: dayLabel.nilIfBlank)
            store.add(place, to: tripId)
            router.popOrPush(.tripPlaces(tripId))
            router.push(.placeDetail(place.id))
        }
    }
}

#Preview {
    let store = PlaceStore(directory: nil)
    let trip = store.addTrip(name: "測試")
    return NavigationStack { PlaceEditorView(tripId: trip.id, placeId: nil) }
        .environment(AppRouter())
        .environment(store)
}
