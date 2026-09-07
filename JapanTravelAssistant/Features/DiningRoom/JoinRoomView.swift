import SwiftUI

/// 輸入家人給的 6 碼代碼加入房間。
struct JoinRoomView: View {
    let prefilledCode: String?

    @Environment(AppRouter.self) private var router
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
    private var canJoin: Bool { RoomCodeGenerator.isValid(normalizedCode) && !isJoining }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("請家人把房間代碼唸給你，或直接掃他手機上的 QR Code。")
                    .font(.app(.body))
                    .foregroundStyle(AppColors.secondaryText)

                if !dependencies.config.isCollaborationConfigured {
                    ErrorBanner(error: .collaborationNotConfigured)
                }
                if let error {
                    ErrorBanner(error: error) { Task { await join() } }
                }

                LargeActionCard(title: "掃 QR Code", subtitle: "對準家人手機上的 QR Code", systemImage: AppIcon.qrCode, tint: AppColors.talk) {
                    focused = nil
                    showScanner = true
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("或輸入房間代碼")
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
            if code.isEmpty, let fixed = DebugSettings.fixedRoomCode { code = fixed }
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

    private func handleScanned(_ payload: String) {
        let scanned: String?
        if let url = URL(string: payload), case .joinRoom(let value)? = DeepLinkParser.parse(url) {
            scanned = value
        } else {
            let plain = RoomCodeGenerator.normalize(payload)
            scanned = RoomCodeGenerator.isValid(plain) ? plain : nil
        }
        guard let scanned else {
            error = UserFacingError(title: "這不是點餐房間的 QR Code", message: "請掃家人 App 裡「QR Code」按鈕顯示的那個。")
            return
        }
        code = scanned
        error = nil
        Task { await join() }
    }

    private func join() async {
        focused = nil
        isJoining = true
        error = nil
        defer { isJoining = false }
        let me = displayName.nilIfBlank ?? "家人"
        DiningSessionStore.rememberDisplayName(me)
        do {
            let session = try await dependencies.roomRepository.joinRoom(code: normalizedCode, displayName: me)
            sessionStore.current = session
            router.push(.room)
        } catch {
            self.error = UserFacingError.from(error)
        }
    }
}

#Preview("有代碼") {
    NavigationStack { JoinRoomView(prefilledCode: "A8F3K2") }
        .environment(AppRouter())
        .environment(DiningSessionStore(defaults: UserDefaults(suiteName: "preview")!))
        .environment(\.dependencies, .preview)
}
