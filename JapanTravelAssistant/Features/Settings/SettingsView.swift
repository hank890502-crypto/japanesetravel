import SwiftUI

/// 設定：AI 幫手、預設地圖、多人點餐狀態。用大卡片單選，不用開關與下拉。
struct SettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(\.dependencies) private var dependencies

    @State private var availableProviders: [NavigationProvider] = [.appleMaps]
    @FocusState private var urlFocused: Bool

    var body: some View {
        @Bindable var settings = settings
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                section(title: "AI 幫手", subtitle: "目前不需要 AI 也能用。之後接上自己的伺服器就能自動翻譯、整理菜單。") {
                    ForEach(AIProviderKind.allCases, id: \.self) { kind in
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
                            Text("伺服器網址")
                                .font(.app(.body))
                                .foregroundStyle(AppColors.secondaryText)
                            TextField("https://…/functions/v1/ai", text: $settings.aiBackendURLText)
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
                                Label("網址格式不對，AI 會維持未啟用", systemImage: AppIcon.warning)
                                    .font(.app(.caption))
                                    .foregroundStyle(AppColors.error)
                            }
                            Text("金鑰只放在伺服器上，App 裡不會有任何金鑰。架設方式見專案內的 docs/AI_BACKEND.md。")
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
                        subtitle: dependencies.config.isCollaborationConfigured ? "家人可以從別的手機加入你的房間。" : "目前只能在這台手機上使用菜單。設定方式見 docs/SUPABASE_SETUP.md。",
                        ok: dependencies.config.isCollaborationConfigured
                    )
                    if let web = dependencies.config.webGuestURL {
                        statusRow(title: "網頁版點餐已開啟", subtitle: "沒裝 App 的家人掃 QR Code 會打開：\(web.absoluteString)", ok: true)
                    }
                }
            }
            .padding(AccessibilityMetrics.screenPadding)
        }
        .scrollDismissesKeyboard(.interactively)
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
        Button(action: action) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(.title2, weight: .semibold))
                    .foregroundStyle(isSelected ? AppColors.accent : AppColors.secondaryText)
                    .padding(.top, 2)
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.app(.cardTitle))
                        .foregroundStyle(AppColors.accent)
                        .padding(.top, 2)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.app(.cardTitle))
                        .foregroundStyle(AppColors.primaryText)
                    if let subtitle {
                        Text(subtitle)
                            .font(.app(.caption))
                            .foregroundStyle(AppColors.secondaryText)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(AccessibilityMetrics.screenPadding)
            .frame(maxWidth: .infinity, minHeight: AccessibilityMetrics.minimumTapTarget, alignment: .leading)
            .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: AccessibilityMetrics.cornerRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: AccessibilityMetrics.cornerRadius, style: .continuous).strokeBorder(isSelected ? AppColors.accent : .clear, lineWidth: 2))
        }
        .buttonStyle(CardPressStyle())
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
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
