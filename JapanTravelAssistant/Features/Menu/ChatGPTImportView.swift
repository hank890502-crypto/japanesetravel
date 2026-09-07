import SwiftUI
import UIKit

/// 「用 ChatGPT 翻譯菜單」：複製提示文字 → 到 ChatGPT 貼上並附照片 → 把回覆貼回來 → 匯入。
struct ChatGPTImportView: View {
    @Environment(AppRouter.self) private var router
    @Environment(MenuDraftStore.self) private var store

    @State private var didCopy = false
    @State private var showPrompt = false
    @State private var pastedText = ""
    @State private var error: UserFacingError?
    @State private var summary: MenuDraftStore.ImportSummary?
    @State private var importedAsReplacement = false
    @State private var pendingImport: [MenuImportParser.ImportedItem] = []
    @State private var askMergeOrReplace = false
    @FocusState private var editorFocused: Bool
    /// 步驟編號的圓圈跟著字體長大，超大字體時數字才不會撐出圓圈
    @ScaledMetric(relativeTo: .title2) private var badgeSize: CGFloat = 40

    private var hasExistingMenu: Bool { !(store.draft?.items.isEmpty ?? true) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let summary {
                    doneView(summary)
                } else {
                    stepsView
                }
            }
            .padding(AccessibilityMetrics.screenPadding)
        }
        .scrollDismissesKeyboard(.interactively)
        .keyboardDoneButton { editorFocused = false }
        .elderlyScreen(title: "用 ChatGPT 翻譯")
    }

    // MARK: - 步驟

    private var stepsView: some View {
        Group {
            Text(hasExistingMenu
                 ? "ChatGPT 翻得比較好。翻完貼回來，會自動補上目前菜單的中文。"
                 : "用 ChatGPT 把菜單照片翻成中文，再貼回來變成共享菜單。")
                .font(.app(.body))
                .foregroundStyle(AppColors.secondaryText)

            stepCard(number: 1, title: "複製提示文字") {
                PrimaryButton(title: didCopy ? "已複製，去 ChatGPT 貼上" : "複製提示文字", systemImage: didCopy ? AppIcon.check : AppIcon.copy) {
                    UIPasteboard.general.string = ChatGPTMenuPrompt.text
                    withAnimation { didCopy = true }
                }
                Button {
                    withAnimation { showPrompt.toggle() }
                } label: {
                    Label(showPrompt ? "收起提示文字" : "看提示文字內容", systemImage: showPrompt ? "chevron.up" : "chevron.down")
                        .font(.app(.caption))
                        .foregroundStyle(AppColors.accent)
                        .frame(minHeight: AccessibilityMetrics.minimumTapTarget)
                }
                if showPrompt {
                    Text(ChatGPTMenuPrompt.text)
                        .font(.system(.footnote))
                        .foregroundStyle(AppColors.primaryText)
                        .textSelection(.enabled)
                        .padding(12)
                        .background(AppColors.screenBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }

            stepCard(number: 2, title: "打開 ChatGPT，貼上，再加上菜單照片") {
                Text("在 ChatGPT 的輸入框長按 → 貼上，按「+」加上菜單照片，送出。")
                    .font(.app(.body))
                    .foregroundStyle(AppColors.secondaryText)
                SecondaryButton(title: "打開 ChatGPT", systemImage: AppIcon.openApp) {
                    openChatGPT()
                }
            }

            stepCard(number: 3, title: "把 ChatGPT 的回覆貼回來") {
                Text("在 ChatGPT 回覆上長按 → 複製，回到這裡按「貼上」。")
                    .font(.app(.body))
                    .foregroundStyle(AppColors.secondaryText)
                SecondaryButton(title: "貼上 ChatGPT 的回覆", systemImage: AppIcon.paste) {
                    if let text = UIPasteboard.general.string?.nilIfBlank {
                        pastedText = text
                        error = nil
                    } else {
                        error = UserFacingError(title: "剪貼簿裡沒有文字", message: "請先到 ChatGPT 長按回覆，選「複製」。")
                    }
                }
                TextEditor(text: $pastedText)
                    .font(.app(.body))
                    .focused($editorFocused)
                    .frame(minHeight: 160)
                    .padding(8)
                    .background(AppColors.screenBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(editorFocused ? AppColors.accent : AppColors.separator, lineWidth: 2)
                    )
                    .overlay(alignment: .topLeading) {
                        if pastedText.isEmpty {
                            Text("回覆會出現在這裡，也可以自己打字")
                                .font(.app(.body))
                                .foregroundStyle(AppColors.secondaryText)
                                .padding(16)
                                .allowsHitTesting(false)
                        }
                    }
                    .accessibilityLabel("ChatGPT 的回覆")
            }

            if let error {
                ErrorBanner(error: error)
            }

            PrimaryButton(title: "匯入菜單", systemImage: AppIcon.check, isEnabled: !pastedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                importPasted()
            }
            .confirmationDialog(
                "目前已經有一份菜單（\(store.draft?.items.count ?? 0) 道菜）",
                isPresented: $askMergeOrReplace,
                titleVisibility: .visible
            ) {
                Button("換成 ChatGPT 的新菜單") { finishImport(replace: true) }
                Button("補進目前的菜單（更新中文與價格）") { finishImport(replace: false) }
                Button("取消", role: .cancel) { pendingImport = [] }
            } message: {
                Text("要用 ChatGPT 的結果換掉目前的菜單，還是補進去？")
            }
        }
    }

    private func stepCard<Content: View>(number: Int, title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Text("\(number)")
                    .font(.app(.cardTitle))
                    .foregroundStyle(.white)
                    .frame(width: badgeSize, height: badgeSize)
                    .background(AppColors.accent, in: Circle())
                    .accessibilityHidden(true)
                Text(title)
                    .font(.app(.cardTitle))
                    .foregroundStyle(AppColors.primaryText)
            }
            content()
        }
        .padding(AccessibilityMetrics.screenPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: AccessibilityMetrics.cornerRadius, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("步驟 \(number)，\(title)")
    }

    private func doneView(_ summary: MenuDraftStore.ImportSummary) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: AppIcon.check)
                    .font(.system(size: 44))
                    .foregroundStyle(AppColors.success)
                VStack(alignment: .leading, spacing: 4) {
                    Text("匯入完成")
                        .font(.app(.sectionTitle))
                    Text(importedAsReplacement || !hasExistingMenu ? "共 \(summary.total) 道菜。" : "更新 \(summary.updated) 道、新增 \(summary.added) 道。")
                        .font(.app(.body))
                        .foregroundStyle(AppColors.secondaryText)
                }
            }
            .padding(AccessibilityMetrics.screenPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: AccessibilityMetrics.cornerRadius, style: .continuous))

            PrimaryButton(title: "檢查菜單", systemImage: AppIcon.restaurant) {
                // 匯入完成頁已經沒有作用：從拍菜單頁進來時用檢查頁「取代」自己，按上一頁會直接回到拍菜單頁
                router.popOrReplace(.menuReview)
            }
        }
    }

    // MARK: - Actions

    private func importPasted() {
        editorFocused = false
        let imported = MenuImportParser.parse(pastedText)
        guard !imported.isEmpty else {
            error = UserFacingError(
                title: "看不懂貼上的內容",
                message: "請確認貼的是 ChatGPT 的回覆，而且是用「日文 | 中文 | 價格」的格式。可以回到 ChatGPT 說「請照原本的格式重新輸出」。"
            )
            return
        }
        error = nil
        if hasExistingMenu {
            pendingImport = imported
            askMergeOrReplace = true
        } else {
            pendingImport = imported
            finishImport(replace: true)
        }
    }

    private func finishImport(replace: Bool) {
        let imported = pendingImport
        pendingImport = []
        importedAsReplacement = replace
        summary = replace ? store.replace(with: imported) : store.merge(imported: imported)
    }

    private func openChatGPT() {
        let app = URL(string: "chatgpt://")!
        let web = URL(string: "https://chatgpt.com")!
        if UIApplication.shared.canOpenURL(app) {
            UIApplication.shared.open(app)
        } else {
            UIApplication.shared.open(web)
        }
    }
}

#Preview {
    NavigationStack { ChatGPTImportView() }
        .environment(AppRouter())
        .environment(MenuDraftStore(directory: nil))
}
