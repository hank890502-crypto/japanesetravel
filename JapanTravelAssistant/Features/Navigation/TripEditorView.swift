import SwiftUI

/// 新增或修改旅程：名稱、日期（可不填）、刪除。
struct TripEditorView: View {
    let tripId: UUID?

    @Environment(AppRouter.self) private var router
    @Environment(PlaceStore.self) private var store

    @State private var name = ""
    @State private var hasDates = false
    @State private var startDate = Date()
    @State private var endDate = Date()
    @State private var loaded = false
    @State private var confirmDelete = false
    @FocusState private var focused: Bool

    private var isNew: Bool { tripId == nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("旅程名稱")
                        .font(.app(.body))
                        .foregroundStyle(AppColors.secondaryText)
                    TextField("例如：9 月名古屋", text: $name)
                        .font(.app(.sectionTitle))
                        .focused($focused)
                        .padding(16)
                        .frame(minHeight: AccessibilityMetrics.minimumTapTarget)
                        .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(focused ? AppColors.accent : AppColors.separator, lineWidth: 2))
                }

                Toggle(isOn: $hasDates) {
                    Text("填日期（可以不填）")
                        .font(.app(.body))
                }
                .tint(AppColors.accent)
                .padding(.horizontal, 4)

                if hasDates {
                    VStack(spacing: 12) {
                        DatePicker("出發", selection: $startDate, displayedComponents: .date)
                        DatePicker("回程", selection: $endDate, in: startDate..., displayedComponents: .date)
                    }
                    .font(.app(.body))
                    .padding(AccessibilityMetrics.screenPadding)
                    .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: AccessibilityMetrics.cornerRadius, style: .continuous))
                    .environment(\.locale, Locale(identifier: "zh_Hant_TW"))
                }

                PrimaryButton(title: isNew ? "建立旅程" : "儲存", systemImage: AppIcon.check, isEnabled: name.nilIfBlank != nil) {
                    save()
                }

                if let tripId, !isNew {
                    Button(role: .destructive) { confirmDelete = true } label: {
                        Label("刪除這趟旅程（連同裡面的地點）", systemImage: AppIcon.delete)
                            .font(.app(.buttonLabel))
                            .foregroundStyle(AppColors.error)
                            .elderlyTapTarget()
                    }
                    .confirmationDialog("確定要刪除這趟旅程嗎？", isPresented: $confirmDelete, titleVisibility: .visible) {
                        Button("刪除旅程與所有地點", role: .destructive) {
                            store.removeTrip(id: tripId)
                            router.popOrPush(.places)
                        }
                        Button("不要刪除", role: .cancel) {}
                    } message: {
                        Text("刪掉就找不回來了。")
                    }
                }
            }
            .padding(AccessibilityMetrics.screenPadding)
        }
        .scrollDismissesKeyboard(.interactively)
        .elderlyScreen(title: isNew ? "新增旅程" : "修改旅程")
        .onAppear {
            guard !loaded else { return }
            loaded = true
            if let tripId, let trip = store.trip(id: tripId) {
                name = trip.name
                if let s = trip.startDate { hasDates = true; startDate = s; endDate = trip.endDate ?? s }
            } else {
                focused = true
            }
        }
    }

    private func save() {
        focused = false
        if let tripId, var trip = store.trip(id: tripId) {
            trip.name = name.trimmingCharacters(in: .whitespaces)
            trip.startDate = hasDates ? startDate : nil
            trip.endDate = hasDates ? endDate : nil
            store.updateTrip(trip)
            router.popOrPush(.tripPlaces(trip.id))
        } else {
            let trip = store.addTrip(name: name, startDate: hasDates ? startDate : nil, endDate: hasDates ? endDate : nil)
            router.popOrPush(.places)
            router.push(.tripPlaces(trip.id))
        }
    }
}

#Preview {
    NavigationStack { TripEditorView(tripId: nil) }
        .environment(AppRouter())
        .environment(PlaceStore(directory: nil))
}
