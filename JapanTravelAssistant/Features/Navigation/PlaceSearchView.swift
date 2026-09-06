import SwiftUI

/// 新增地點：打關鍵字搜尋（Apple 地圖資料），點一下就存；或改成自己輸入。
struct PlaceSearchView: View {
    @Environment(AppRouter.self) private var router
    @Environment(PlaceStore.self) private var store
    @Environment(\.dependencies) private var dependencies

    @State private var query = ""
    @State private var results: [PlaceSearchResult] = []
    @State private var isSearching = false
    @State private var didSearch = false
    @State private var error: UserFacingError?
    @FocusState private var focused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("輸入飯店、車站或店名，可以用中文或日文。例如：東京駅、名古屋 ホテル。")
                    .font(.app(.body))
                    .foregroundStyle(AppColors.secondaryText)

                HStack(spacing: 10) {
                    TextField("要找什麼地方？", text: $query)
                        .font(.app(.sectionTitle))
                        .focused($focused)
                        .submitLabel(.search)
                        .onSubmit { Task { await search() } }
                        .padding(16)
                        .frame(minHeight: AccessibilityMetrics.minimumTapTarget)
                        .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(focused ? AppColors.accent : AppColors.separator, lineWidth: 2))
                    Button {
                        Task { await search() }
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.system(.title2, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: AccessibilityMetrics.minimumTapTarget, height: AccessibilityMetrics.minimumTapTarget)
                            .background(AppColors.accent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .accessibilityLabel("搜尋")
                    .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty || isSearching)
                }

                if let error {
                    ErrorBanner(error: error) { Task { await search() } }
                }

                if isSearching {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("搜尋中…").font(.app(.body)).foregroundStyle(AppColors.secondaryText)
                    }
                } else if didSearch && results.isEmpty && error == nil {
                    Text("找不到。試試加上城市名稱，或改用「自己輸入地址」。")
                        .font(.app(.body))
                        .foregroundStyle(AppColors.secondaryText)
                }

                ForEach(results) { result in
                    Button {
                        save(result)
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: result.suggestedCategory.systemImage)
                                .font(.app(.cardTitle))
                                .foregroundStyle(PlacesView.tint(for: result.suggestedCategory))
                                .frame(width: 36)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(result.name)
                                    .font(.app(.cardTitle))
                                    .foregroundStyle(AppColors.primaryText)
                                    .multilineTextAlignment(.leading)
                                if let address = result.address {
                                    Text(address)
                                        .font(.app(.caption))
                                        .foregroundStyle(AppColors.secondaryText)
                                        .multilineTextAlignment(.leading)
                                }
                            }
                            Spacer()
                            Text("存起來")
                                .font(.system(.caption, weight: .semibold))
                                .foregroundStyle(AppColors.accent)
                        }
                        .padding(AccessibilityMetrics.screenPadding)
                        .frame(maxWidth: .infinity, minHeight: AccessibilityMetrics.minimumTapTarget, alignment: .leading)
                        .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: AccessibilityMetrics.cornerRadius, style: .continuous))
                    }
                    .buttonStyle(CardPressStyle())
                    .accessibilityLabel("\(result.name)，\(result.address ?? "")")
                    .accessibilityHint("點一下存起來")
                }

                SecondaryButton(title: "自己輸入名稱和地址", systemImage: AppIcon.edit) {
                    router.push(.placeEditor(nil))
                }
                .padding(.top, 8)
            }
            .padding(AccessibilityMetrics.screenPadding)
        }
        .scrollDismissesKeyboard(.interactively)
        .elderlyScreen(title: "新增地點")
        .onAppear { focused = true }
    }

    private func search() async {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        focused = false
        isSearching = true
        error = nil
        defer { isSearching = false; didSearch = true }
        let near = await dependencies.location.currentLocation()
        do {
            results = try await dependencies.placeSearch.search(text, near: near)
        } catch {
            results = []
            self.error = UserFacingError.from(error)
        }
    }

    private func save(_ result: PlaceSearchResult) {
        let place = result.toPlace()
        store.add(place)
        router.popOrPush(.places)
        router.push(.placeDetail(place.id))
    }
}

#Preview {
    NavigationStack { PlaceSearchView() }
        .environment(AppRouter())
        .environment(PlaceStore(directory: nil))
        .environment(\.dependencies, .preview)
}
