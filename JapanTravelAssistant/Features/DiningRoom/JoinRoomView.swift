import SwiftUI

/// 輸入家人給的 6 碼代碼加入房間。
struct JoinRoomView: View {
    let prefilledCode: String?

    @Environment(AppRouter.self) private var router
    @Environment(RoomSessionCoordinator.self) private var coordinator
    @Environment(DiningSessionStore.self) private var sessionStore
    @Environment(\.dependencies) private var dependencies

    @State private var code = ""
    @State private var displayName = DiningSessionStore.rememberedDisplayName()
    @State private var isJoining = false
    @State private var error: UserFacingError?
    @State private var showScanner = false
    @FocusState private var focused: Field?

    private enum Field { case code, name }
    private var normalizedCode: String { RoomCodeGenerator.normalize(code) }
    private var isConfigured: Bool { dependencies.config.isCollaborationConfigured }
    private var canJoin: Bool { isConfigured && RoomCodeGenerator.isValid(normalizedCode) && !isJoining }
    /// 這台手機目前所在（還能用）的房間
    private var currentRoom: DiningRoom? {
        guard let room = sessionStore.current?.room, room.isJoinable else { return nil }
        return room
    }
    /// 輸入的代碼就是目前所在的房間
    private var isCurrentRoomCode: Bool { currentRoom?.roomCode == normalizedCode }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("請家人把房間代碼唸給你，或直接掃他手機上的 QR Code。")
                    .font(.app(.body))
                    .foregroundStyle(AppColors.secondaryText)

                if !isConfigured {
                    // 這台手機根本沒連上多人點餐：把「加入」關掉，不要讓長輩以為是代碼打錯
                    ErrorBanner(error: UserFacingError(
                        title: "這台手機還不能加入家人的點餐",
                        message: "這個版本還沒有連上多人點餐。請家人幫忙檢查 App 的設定，或改用家人手機上的網頁版。",
                        isRetryable: false
                    ))
                }
                if let error {
                    ErrorBanner(error: error) { Task { await join() } }
                }

                if let currentRoom {
                    if isCurrentRoomCode {
                        LargeActionCard(title: "你已經在「\(currentRoom.name)」裡了", subtitle: "不用再加入，直接回到點餐畫面", systemImage: AppIcon.joinRoom, tint: AppColors.go) {
                            router.push(.room)
                        }
                    } else {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "info.circle.fill")
                                .font(.app(.cardTitle))
                                .foregroundStyle(AppColors.accent)
                                .accessibilityHidden(true)
                            Text("你現在在「\(currentRoom.name)」房間。加入新的房間後，就會離開它（你點的東西會留著）。")
                                .font(.app(.body))
                                .foregroundStyle(AppColors.primaryText)
                        }
                        .padding(AccessibilityMetrics.screenPadding)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: AccessibilityMetrics.cornerRadius, style: .continuous))
                        .accessibilityElement(children: .combine)
                    }
                }

                if isConfigured {
                    LargeActionCard(title: "掃 QR Code", subtitle: "對準家人手機上的 QR Code", systemImage: AppIcon.qrCode, tint: AppColors.talk) {
                        focused = nil
                        showScanner = true
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(isConfigured ? "或輸入房間代碼" : "房間代碼")
                        .font(.app(.body))
                        .foregroundStyle(AppColors.secondaryText)
                    TextField("例如 A8F3K2", text: $code)
                        .font(.system(.largeTitle, design: .monospaced, weight: .bold))
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .keyboardType(.asciiCapable)
                        .focused($focused, equals: .code)
                        .multilineTextAlignment(.center)
                        .padding(16)
                        .frame(minHeight: 72)
                        .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(focused == .code ? AppColors.accent : AppColors.separator, lineWidth: 2))
                        .onChange(of: code) { _, newValue in
                            let cleaned = String(RoomCodeGenerator.normalize(newValue).prefix(RoomCodeGenerator.length))
                            if cleaned != newValue { code = cleaned }
                        }
                        .accessibilityLabel("房間代碼")
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("我的稱呼（家人看到的名字）")
                        .font(.app(.body))
                        .foregroundStyle(AppColors.secondaryText)
                    TextField("例如：媽媽、小美", text: $displayName)
                        .font(.app(.sectionTitle))
                        .focused($focused, equals: .name)
                        .padding(16)
                        .frame(minHeight: AccessibilityMetrics.minimumTapTarget)
                        .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(focused == .name ? AppColors.accent : AppColors.separator, lineWidth: 2))
                        .onChange(of: displayName) { _, newValue in
                            let clamped = RoomMember.clampDisplayName(newValue)
                            if clamped != newValue { displayName = clamped }
                        }
                    Text(displayName.count >= RoomMember.maxDisplayNameLength
                         ? "稱呼最多 \(RoomMember.maxDisplayNameLength) 個字，已經到上限了。"
                         : "稱呼最多 \(RoomMember.maxDisplayNameLength) 個字。")
                        .font(.app(.caption))
                        .foregroundStyle(AppColors.secondaryText)
                }

                PrimaryButton(title: isJoining ? "加入中…" : "加入", systemImage: AppIcon.joinRoom, isLoading: isJoining, isEnabled: canJoin) {
                    Task { await join() }
                }
            }
            .padding(AccessibilityMetrics.screenPadding)
        }
        .scrollDismissesKeyboard(.interactively)
        .keyboardDoneButton { focused = nil }
        .elderlyScreen(title: "加入家人的點餐")
        .onAppear {
            if let prefilledCode, code.isEmpty { code = RoomCodeGenerator.normalize(prefilledCode) }
            focused = code.isEmpty ? .code : .name
            if DebugLaunchOptions.hasFlag("-openQRScanner") {
                focused = nil
                showScanner = true
            }
        }
        .fullScreenCover(isPresented: $showScanner) {
            QRCodeScanSheet(
                onCode: { payload in
                    showScanner = false
                    handleScanned(payload)
                },
                onClose: { showScanner = false }
            )
        }
    }

    /// 只接受 App 專用連結、設定裡那個網頁版的連結，或直接印著代碼的 QR；
    /// 餐廳桌上的官網、優惠 QR（也常帶 ?code=）一律不算，不會拿去加入。
    private func handleScanned(_ payload: String) {
        let scanned: String?
        if let url = URL(string: payload), case .joinRoom(let value)? = DeepLinkParser.parse(url, webGuestHost: dependencies.config.webGuestURL?.host) {
            scanned = value
        } else if !payload.contains("://") {
            let plain = RoomCodeGenerator.normalize(payload)
            scanned = RoomCodeGenerator.isValid(plain) ? plain : nil
        } else {
            scanned = nil
        }
        guard let scanned, RoomCodeGenerator.isValid(scanned) else {
            error = .notRoomQRCode
            return
        }
        code = scanned
        error = nil
        if isCurrentRoomCode {
            router.push(.room)   // 掃到的就是目前所在的房間：直接回去，不重新加入
            return
        }
        Task { await join() }
    }

    private func join() async {
        guard isConfigured else { return }
        guard RoomCodeGenerator.isValid(normalizedCode) else {
            error = UserFacingError(title: "代碼不完整", message: "房間代碼是 6 個英文字母或數字，請再確認一次。", isRetryable: false)
            return
        }
        focused = nil
        isJoining = true
        error = nil
        defer { isJoining = false }
        let me = RoomMember.clampDisplayName(displayName.nilIfBlank ?? "家人")
        DiningSessionStore.rememberDisplayName(me)
        do {
            let session = try await dependencies.roomRepository.joinRoom(code: normalizedCode, displayName: me)
            coordinator.enter(session)
            router.push(.room)
        } catch {
            self.error = UserFacingError.from(error)
        }
    }
}

#Preview("有代碼") {
    let store = DiningSessionStore(defaults: UserDefaults(suiteName: "preview")!)
    NavigationStack { JoinRoomView(prefilledCode: "A8F3K2") }
        .environment(AppRouter())
        .environment(store)
        .environment(RoomSessionCoordinator.preview(sessionStore: store))
        .environment(\.dependencies, .preview)
}
