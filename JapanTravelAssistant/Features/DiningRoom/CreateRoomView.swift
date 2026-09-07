import SwiftUI

/// 建立用餐房間：取個名字、我的稱呼 → 建房 + 上傳菜單 → 進入房間。
struct CreateRoomView: View {
    @Environment(AppRouter.self) private var router
    @Environment(MenuDraftStore.self) private var draftStore
    @Environment(RoomSessionCoordinator.self) private var coordinator
    @Environment(\.dependencies) private var dependencies

    @State private var roomName = ""
    @State private var displayName = DiningSessionStore.rememberedDisplayName()
    @State private var isCreating = false
    @State private var error: UserFacingError?
    @FocusState private var focused: Field?

    private enum Field { case room, name }
    private var items: [MenuItemDraft] { draftStore.draft?.items ?? [] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("菜單準備好了")
                        .font(.app(.sectionTitle))
                    Text("共 \(items.count) 道菜。建立房間後，家人輸入代碼就能一起點。")
                        .font(.app(.body))
                        .foregroundStyle(AppColors.secondaryText)
                }
                .padding(AccessibilityMetrics.screenPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: AccessibilityMetrics.cornerRadius, style: .continuous))

                if !dependencies.config.isCollaborationConfigured {
                    ErrorBanner(error: UserFacingError(
                        title: "目前沒有連上多人點餐",
                        message: "還是可以建立房間自己點，但家人無法從別的手機加入。",
                        isRetryable: false
                    ))
                }

                if let error {
                    ErrorBanner(error: error) { Task { await create() } }
                }

                field(label: "這一餐叫什麼？", text: $roomName, placeholder: "例如：酒津屋晚餐", focus: .room)
                field(label: "我的稱呼（家人看到的名字）", text: $displayName, placeholder: "例如：爸爸、小明", focus: .name, hint: displayNameHint)
                    .onChange(of: displayName) { _, newValue in
                        let clamped = RoomMember.clampDisplayName(newValue)
                        if clamped != newValue { displayName = clamped }
                    }

                PrimaryButton(title: isCreating ? "建立中…" : "建立房間", systemImage: AppIcon.joinRoom, isLoading: isCreating, isEnabled: !items.isEmpty) {
                    Task { await create() }
                }
            }
            .padding(AccessibilityMetrics.screenPadding)
        }
        .scrollDismissesKeyboard(.interactively)
        .keyboardDoneButton { focused = nil }
        .elderlyScreen(title: "建立共享菜單")
        .onAppear {
            if roomName.isEmpty { roomName = draftStore.draft?.restaurantName.nilIfBlank ?? "" }
        }
    }

    private var displayNameHint: String {
        displayName.count >= RoomMember.maxDisplayNameLength
            ? "稱呼最多 \(RoomMember.maxDisplayNameLength) 個字，已經到上限了。"
            : "稱呼最多 \(RoomMember.maxDisplayNameLength) 個字。"
    }

    private func field(label: String, text: Binding<String>, placeholder: String, focus: Field, hint: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.app(.body))
                .foregroundStyle(AppColors.secondaryText)
            TextField(placeholder, text: text)
                .font(.app(.sectionTitle))
                .focused($focused, equals: focus)
                .padding(16)
                .frame(minHeight: AccessibilityMetrics.minimumTapTarget)
                .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(focused == focus ? AppColors.accent : AppColors.separator, lineWidth: 2))
            if let hint {
                Text(hint)
                    .font(.app(.caption))
                    .foregroundStyle(AppColors.secondaryText)
            }
        }
    }

    private func create() async {
        draftStore.fillMissingReadings()
        guard let draft = draftStore.draft else { return }
        focused = nil
        isCreating = true
        error = nil
        defer { isCreating = false }
        let name = roomName.nilIfBlank ?? "一起點餐"
        let me = RoomMember.clampDisplayName(displayName.nilIfBlank ?? "我")
        DiningSessionStore.rememberDisplayName(me)
        do {
            let session = try await dependencies.roomRepository.createRoom(name: name, hostDisplayName: me)
            var bundle = draft.toBundle()
            bundle.menu.restaurantName = bundle.menu.restaurantName ?? name
            _ = try await dependencies.menuRepository.saveMenu(bundle, toRoom: session.room.id)
            coordinator.enter(session)
            router.push(.room)
        } catch {
            self.error = UserFacingError.from(error)
        }
    }
}

#Preview {
    let store = MenuDraftStore(directory: nil)
    store.draft = DebugLaunchOptions.sampleDraft(arguments: ["-openRoute", "createRoom"])
    let sessionStore = DiningSessionStore(defaults: UserDefaults(suiteName: "preview")!)
    return NavigationStack { CreateRoomView() }
        .environment(AppRouter())
        .environment(store)
        .environment(sessionStore)
        .environment(RoomSessionCoordinator.preview(sessionStore: sessionStore))
        .environment(\.dependencies, .preview)
}
