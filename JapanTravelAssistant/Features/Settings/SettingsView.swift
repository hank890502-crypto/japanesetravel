import SwiftUI

/// 設定：AI 幫手、預設地圖、多人點餐狀態。用大卡片單選，不用開關與下拉。
struct SettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(\.dependencies) private var dependencies

    @State private var availableProviders: [NavigationProvider] = [.appleMaps]
    @FocusState private var urlFocused: Bool
    @FocusState private var tokenFocused: Bool

    /// 「測試用（假資料）」只給開發時用，正式版不讓長輩看到
    private var aiProviders: [AIProviderKind] {
        #if DEBUG
        AIProviderKind.allCases
        #else
        AIProviderKind.allCases.filter { $0 != .mock }
        #endif
    }

    var body: some View {
        @Bindable var settings = settings
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                section(title: "AI 幫手", subtitle: "不用 AI 也能正常使用。想讓 App 自動翻譯、整理菜單，可以在這裡選。") {
                    ForEach(aiProviders, id: \.self) { kind in
                        choiceCard(title: kind.displayName, subtitle: kind.explanation, isSelected: settings.aiProvider == kind) {
                            settings.aiProvider = kind
                        }
                        if kind == .appleIntelligence, let reason = AppleIntelligence.availability.reason {
                            Label(reason, systemImage: AppIcon.warning)
                                .font(.app(.caption))
                                .foregroundStyle(AppColors.secondaryText)
                                .padding(.horizontal, 4)
                        }
                    }
                    if settings.aiProvider == .remoteBackend {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("AI 服務的網址（請家人幫你填）")
                                .font(.app(.body))
                                .foregroundStyle(AppColors.secondaryText)
                            TextField("由家人貼上網址", text: $settings.aiBackendURLText)
                                .font(.app(.body))
                                .keyboardType(.URL)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .focused($urlFocused)
                                .padding(16)
                                .frame(minHeight: AccessibilityMetrics.minimumTapTarget)
                                .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(urlFocused ? AppColors.accent : AppColors.separator, lineWidth: 2))
                            if settings.aiBackendURL == nil, !settings.aiBackendURLText.isEmpty {
                                Label("這個網址看起來不完整，AI 幫手暫時不會啟用。請家人再確認一次。", systemImage: AppIcon.warning)
                                    .font(.app(.caption))
                                    .foregroundStyle(AppColors.error)
                            }
                            Text("伺服器密碼（沒有可以不填）")
                                .font(.app(.body))
                                .foregroundStyle(AppColors.secondaryText)
                            TextField("架設伺服器時自己設定的那一串", text: $settings.aiBackendTokenText)
                                .font(.app(.body))
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .focused($tokenFocused)
                                .padding(16)
                                .frame(minHeight: AccessibilityMetrics.minimumTapTarget)
                                .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(tokenFocused ? AppColors.accent : AppColors.separator, lineWidth: 2))
                            Text("有設定密碼的伺服器只接受這個 App 的呼叫，別人拿到網址也用不了。")
                                .font(.app(.caption))
                                .foregroundStyle(AppColors.secondaryText)
                            Text("這一部分請家人或幫你安裝 App 的人設定，你不用自己填。")
                                .font(.app(.caption))
                                .foregroundStyle(AppColors.secondaryText)
                        }
                    }
                }

                section(title: "預設用哪個地圖帶路", subtitle: "按「帶我去」時會列出所有地圖讓你當下選，這裡選的排在最前面。Google 地圖沒安裝會開網頁版；Yahoo! カーナビ 要先安裝。") {
                    ForEach(availableProviders) { provider in
                        choiceCard(title: provider.displayName, subtitle: nil, systemImage: provider.systemImage, isSelected: settings.navigationProvider == provider) {
                            settings.navigationProvider = provider
                        }
                    }
                    if !availableProviders.contains(.yahooCarNavi) {
                        Text("自駕想用 Yahoo! カーナビ：先到 App Store 安裝（免費），之後這裡就會出現。")
                            .font(.app(.caption))
                            .foregroundStyle(AppColors.secondaryText)
                    }
                }

                section(title: "多人點餐", subtitle: nil) {
                    statusRow(
                        title: dependencies.config.isCollaborationConfigured ? "已連線" : "尚未設定",
                        subtitle: dependencies.config.isCollaborationConfigured ? "家人可以從別的手機加入你的房間。" : "目前只能在這台手機上使用菜單。想讓家人一起點餐，請幫你安裝 App 的人設定。",
                        ok: dependencies.config.isCollaborationConfigured
                    )
                    if dependencies.config.webGuestURL != nil {
                        statusRow(title: "網頁版點餐已開啟", subtitle: "沒裝 App 的家人掃 QR Code 也能一起點餐。", ok: true)
                    }
                }
            }
            .padding(AccessibilityMetrics.screenPadding)
        }
        .scrollDismissesKeyboard(.interactively)
        .keyboardDoneButton { urlFocused = false }
        .elderlyScreen(title: "設定")
        .task {
            availableProviders = dependencies.navigation.availableProviders()
            if !availableProviders.contains(settings.navigationProvider) { settings.navigationProvider = .appleMaps }
        }
    }

    private func section<Content: View>(title: String, subtitle: String?, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.app(.sectionTitle))
                .accessibilityAddTraits(.isHeader)
            if let subtitle {
                Text(subtitle)
                    .font(.app(.caption))
                    .foregroundStyle(AppColors.secondaryText)
            }
            content()
        }
    }

    private func choiceCard(title: String, subtitle: String?, systemImage: String? = nil, isSelected: Bool, action: @escaping () -> Void) -> some View {
        ChoiceCard(title: title, subtitle: subtitle, systemImage: systemImage, isSelected: isSelected, action: action)
    }

    private func statusRow(title: String, subtitle: String, ok: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: ok ? AppIcon.check : AppIcon.warning)
                .font(.app(.cardTitle))
                .foregroundStyle(ok ? AppColors.success : AppColors.error)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.app(.cardTitle))
                Text(subtitle).font(.app(.caption)).foregroundStyle(AppColors.secondaryText)
            }
        }
        .padding(AccessibilityMetrics.screenPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: AccessibilityMetrics.cornerRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    NavigationStack { SettingsView() }
        .environment(SettingsStore(defaults: UserDefaults(suiteName: "preview")!))
        .environment(\.dependencies, .preview)
}
