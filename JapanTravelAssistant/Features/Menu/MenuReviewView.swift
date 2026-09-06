import SwiftUI

/// 檢查與修改辨識結果。每道菜一張卡片，點進去改；可新增、刪除；
/// 沒配到價格的文字另外列出，讓使用者挑出是菜的加入。
struct MenuReviewView: View {
    @Environment(AppRouter.self) private var router
    @Environment(MenuDraftStore.self) private var store
    @Environment(\.dependencies) private var dependencies

    @State private var editingItem: MenuItemDraft?
    @State private var showSourceImages = false
    @State private var showOtherLines = false
    @State private var translationBatch: TranslationBatch?
    @State private var isTranslating = false
    @State private var translationError: UserFacingError?
    @State private var didAutoTranslate = false
    @State private var collapsedSections: Set<String> = []
    @State private var showAIUnavailable = false
    @State private var isAIAnalyzing = false
    @State private var aiSummary: String?

    private var items: [MenuItemDraft] { store.draft?.items ?? [] }
    private var otherLines: [MenuItemDraft] { store.draft?.otherLines ?? [] }
    private var groups: [MenuDraft.Group] { store.draft?.groupedItems ?? [] }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text(introText)
                    .font(.app(.body))
                    .foregroundStyle(AppColors.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if !store.sourceImages.isEmpty {
                    SecondaryButton(title: "看原始照片", systemImage: AppIcon.image) {
                        showSourceImages = true
                    }
                }

                if let translationError {
                    ErrorBanner(error: translationError) { translate() }
                }

                if !items.isEmpty && items.contains(where: { $0.chineseName.nilIfBlank == nil }) {
                    PrimaryButton(title: isTranslating ? "翻譯中…" : "幫我翻成中文", systemImage: AppIcon.translate, isLoading: isTranslating) {
                        translate()
                    }
                }

                if !items.isEmpty {
                    SecondaryButton(title: "用 ChatGPT 翻得更好", systemImage: AppIcon.sparkles) {
                        router.push(.chatGPTImport)
                    }
                }

                if !items.isEmpty || !otherLines.isEmpty {
                    SecondaryButton(title: isAIAnalyzing ? "AI 整理中…" : "AI 幫我整理菜單", systemImage: "wand.and.stars", isEnabled: !isAIAnalyzing) {
                        Task { await runAI() }
                    }
                    if showAIUnavailable {
                        AIUnavailableBanner()
                    }
                    if let aiSummary {
                        Label(aiSummary, systemImage: AppIcon.check)
                            .font(.app(.body))
                            .foregroundStyle(AppColors.success)
                    }
                }

                ForEach(groups) { group in
                    if group.section != nil || groups.count > 1 {
                        sectionHeader(group)
                    }
                    if !collapsedSections.contains(group.id) {
                        ForEach(group.items) { item in
                            itemCard(item)
                        }
                    }
                }

                SecondaryButton(title: "新增一道菜", systemImage: AppIcon.add) {
                    editingItem = MenuItemDraft(japaneseName: "")
                }

                if !otherLines.isEmpty {
                    otherLinesSection
                }

                PrimaryButton(title: "下一步：建立共享菜單", systemImage: AppIcon.joinRoom, isEnabled: !items.isEmpty) {
                    router.push(.createRoom)
                }
                .padding(.top, 8)
            }
            .padding(AccessibilityMetrics.screenPadding)
        }
        .elderlyScreen(title: "檢查菜單")
        .onAppear {
            // 完全沒有配到價格的菜時，直接把其他文字展開
            if items.isEmpty && !otherLines.isEmpty { showOtherLines = true }
            // 第一次進來就自動補拼音、自動翻譯（詞彙表 + 系統離線翻譯）
            if !didAutoTranslate {
                didAutoTranslate = true
                store.fillMissingReadings()
                translate()
            }
        }
        .appleTranslation(
            batch: translationBatch,
            onResult: { result in
                applyTranslations(result)
                isTranslating = false
                translationBatch = nil
            },
            onError: { error in
                isTranslating = false
                translationBatch = nil
                translationError = error
            }
        )
        .sheet(item: $editingItem) { item in
            MenuItemEditorView(
                item: item,
                isNew: !items.contains { $0.id == item.id },
                availableSections: store.draft?.sectionNames ?? [],
                onSave: { updated in
                    var saved = updated
                    if saved.reading?.nilIfBlank == nil || items.first(where: { $0.id == saved.id })?.japaneseName != saved.japaneseName {
                        saved.reading = JapaneseReading.romaji(for: saved.japaneseName)
                    }
                    store.upsert(saved)
                    editingItem = nil
                },
                onDelete: {
                    store.remove(id: item.id)
                    editingItem = nil
                },
                onCancel: { editingItem = nil }
            )
        }
        .sheet(isPresented: $showSourceImages) {
            SourceImagesSheet(images: store.sourceImages) { showSourceImages = false }
        }
    }

    // MARK: - 分類與卡片

    private func sectionHeader(_ group: MenuDraft.Group) -> some View {
        let isCollapsed = collapsedSections.contains(group.id)
        return Button {
            withAnimation {
                if isCollapsed { collapsedSections.remove(group.id) } else { collapsedSections.insert(group.id) }
            }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.section ?? "沒有分類")
                        .font(.app(.sectionTitle))
                        .foregroundStyle(AppColors.primaryText)
                    if let chinese = group.sectionChinese {
                        Text(chinese)
                            .font(.app(.body))
                            .foregroundStyle(AppColors.secondaryText)
                    }
                }
                Spacer()
                Text("\(group.items.count) 道")
                    .font(.app(.body))
                    .foregroundStyle(AppColors.secondaryText)
                Image(systemName: isCollapsed ? "chevron.down" : "chevron.up")
                    .font(.app(.body).weight(.semibold))
                    .foregroundStyle(AppColors.accent)
            }
            .padding(.horizontal, 4)
            .padding(.top, 12)
            .frame(maxWidth: .infinity, minHeight: AccessibilityMetrics.minimumTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("分類 \(group.section ?? "沒有分類")，\(group.items.count) 道")
        .accessibilityHint(isCollapsed ? "點一下展開" : "點一下收起")
    }

    private func itemCard(_ item: MenuItemDraft) -> some View {
        Button {
            editingItem = item
        } label: {
            MenuItemCard(
                japaneseName: item.japaneseName,
                chineseName: item.chineseName,
                reading: item.reading,
                price: item.price,
                note: item.note,
                optionsSummary: item.optionsSummary,
                isLowConfidence: (item.sourceConfidence ?? 1) < 0.5
            ) {
                VStack(spacing: 4) {
                    Image(systemName: AppIcon.edit)
                        .font(.system(.title2, weight: .semibold))
                    Text("修改")
                        .font(.system(.caption, weight: .semibold))
                }
                .foregroundStyle(AppColors.accent)
                .frame(minWidth: 56)
            }
        }
        .buttonStyle(CardPressStyle())
        .accessibilityLabel("\(item.japaneseName)，\(item.chineseName.nilIfBlank ?? "沒有中文")，\(PriceFormatter.string(item.price) ?? "沒有價格")")
        .accessibilityHint("點一下修改")
    }

    // MARK: - AI

    /// 把目前的菜與其他文字交給 AI 重新整理（中文、分類、選項、拼音），結果合併進草稿。
    private func runAI() async {
        guard dependencies.ai.isEnabled else {
            withAnimation { showAIUnavailable = true }
            return
        }
        showAIUnavailable = false
        aiSummary = nil
        translationError = nil
        isAIAnalyzing = true
        defer { isAIAnalyzing = false }
        let blocks = (items.map { $0.ocrText ?? "\($0.japaneseName) \($0.priceText)" } + otherLines.map { $0.ocrText ?? $0.japaneseName })
            .map { RecognizedTextBlock(text: $0, confidence: 1, boundingBox: .zero) }
        do {
            let analysis = try await dependencies.ai.analyzeMenu(textBlocks: blocks, image: store.sourceImages.first)
            let summary = store.merge(imported: analysis.importedItems)
            if let name = analysis.restaurantName?.nilIfBlank, var draft = store.draft, draft.restaurantName.isEmpty {
                draft.restaurantName = name
                store.draft = draft
            }
            aiSummary = "AI 整理完成：更新 \(summary.updated) 道、新增 \(summary.added) 道（\(dependencies.ai.providerName)）"
        } catch {
            translationError = UserFacingError.from(error)
        }
    }

    // MARK: - 翻譯

    /// 先用內建詞彙表（立刻、離線），剩下的交給系統翻譯（iOS 18）。
    private func translate() {
        translationError = nil
        var remaining: [TranslationBatch.Entry] = []
        for item in items where item.chineseName.nilIfBlank == nil {
            if let chinese = MenuGlossary.bundled.translate(item.japaneseName) {
                var updated = item
                updated.chineseName = chinese
                store.upsert(updated)
            } else {
                remaining.append(.init(id: item.id.uuidString, text: item.japaneseName))
            }
        }
        if let draft = store.draft {
            for section in draft.sectionNames where draft.sectionChineseNames[section]?.nilIfBlank == nil {
                if let chinese = MenuGlossary.bundled.translate(section) {
                    store.setSectionChineseName(chinese, for: section)
                } else {
                    remaining.append(.init(id: "section:\(section)", text: section))
                }
            }
        }
        guard !remaining.isEmpty else { return }
        guard AppleTranslation.isAvailable else {
            translationError = UserFacingError(title: "需要 iOS 18 才能離線翻譯", message: "詞彙表認得的已經翻好了，其他請自己輸入中文。", isRetryable: false)
            return
        }
        isTranslating = true
        translationBatch = TranslationBatch(entries: remaining)
    }

    private func applyTranslations(_ result: [String: String]) {
        for (key, value) in result where key.hasPrefix("section:") {
            let section = String(key.dropFirst("section:".count))
            if store.draft?.sectionChineseNames[section]?.nilIfBlank == nil, let chinese = value.nilIfBlank {
                store.setSectionChineseName(chinese, for: section)
            }
        }
        for item in items {
            guard item.chineseName.nilIfBlank == nil,
                  let translated = result[item.id.uuidString]?.nilIfBlank else { continue }
            var updated = item
            updated.chineseName = translated
            store.upsert(updated)
        }
    }

    private var introText: String {
        if items.isEmpty && otherLines.isEmpty {
            return "還沒有菜，按下面的「新增一道菜」開始。"
        }
        if items.isEmpty {
            return "照片裡沒有找到「菜名加價格」的組合。下面是辨識到的文字，是菜的請點「加入」。"
        }
        return "檢查一下，有錯的請點那道菜修改。中文可以不填。"
    }

    private var otherLinesSection: some View {
        VStack(spacing: 12) {
            Button {
                withAnimation { showOtherLines.toggle() }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("其他辨識到的文字（\(otherLines.count) 行）")
                            .font(.app(.cardTitle))
                            .foregroundStyle(AppColors.primaryText)
                        Text("店名、分類、說明通常在這裡。如果有漏掉的菜，點「加入」。")
                            .font(.app(.caption))
                            .foregroundStyle(AppColors.secondaryText)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer()
                    Image(systemName: showOtherLines ? "chevron.up" : "chevron.down")
                        .font(.app(.cardTitle))
                        .foregroundStyle(AppColors.secondaryText)
                }
                .padding(AccessibilityMetrics.screenPadding)
                .frame(maxWidth: .infinity, minHeight: AccessibilityMetrics.minimumTapTarget)
                .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: AccessibilityMetrics.cornerRadius, style: .continuous))
            }
            .buttonStyle(CardPressStyle())
            .accessibilityLabel("其他辨識到的文字，\(otherLines.count) 行")
            .accessibilityHint(showOtherLines ? "收起" : "展開")

            if showOtherLines {
                ForEach(otherLines) { line in
                    HStack(spacing: 12) {
                        Text(line.japaneseName)
                            .font(.app(.body))
                            .foregroundStyle(AppColors.primaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button {
                            if let promoted = store.promoteOtherLine(id: line.id) {
                                editingItem = promoted
                            }
                        } label: {
                            Label("加入", systemImage: AppIcon.add)
                                .font(.app(.buttonLabel))
                                .foregroundStyle(AppColors.accent)
                                .frame(minHeight: AccessibilityMetrics.minimumTapTarget)
                                .padding(.horizontal, 8)
                        }
                        .accessibilityLabel("把「\(line.japaneseName)」加入菜單")
                        Button {
                            store.discardOtherLine(id: line.id)
                        } label: {
                            Image(systemName: AppIcon.close)
                                .font(.app(.buttonLabel))
                                .foregroundStyle(AppColors.secondaryText)
                                .frame(width: AccessibilityMetrics.minimumTapTarget, height: AccessibilityMetrics.minimumTapTarget)
                        }
                        .accessibilityLabel("不要「\(line.japaneseName)」")
                    }
                    .padding(.horizontal, AccessibilityMetrics.screenPadding)
                    .padding(.vertical, 8)
                    .background(AppColors.cardBackground.opacity(0.6), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
        }
    }
}

/// 原始照片，可放大，多頁上下排列。
private struct SourceImagesSheet: View {
    let images: [UIImage]
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button(action: onClose) {
                    HStack(spacing: 6) {
                        Image(systemName: AppIcon.close)
                        Text("關閉")
                    }
                    .font(.app(.buttonLabel))
                    .frame(minHeight: AccessibilityMetrics.minimumTapTarget)
                    .padding(.horizontal, 20)
                }
            }
            .padding(.horizontal, AccessibilityMetrics.screenPadding)
            ScrollView([.horizontal, .vertical]) {
                VStack(spacing: 16) {
                    ForEach(Array(images.enumerated()), id: \.offset) { _, image in
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(width: UIScreen.main.bounds.width * 1.6)
                    }
                }
            }
        }
        .background(AppColors.screenBackground)
    }
}

#Preview {
    let store = MenuDraftStore(directory: nil)
    store.draft = DebugLaunchOptions.sampleDraft(arguments: ["-openRoute", "menuReview"])
    return NavigationStack { MenuReviewView() }
        .environment(AppRouter())
        .environment(store)
        .environment(\.dependencies, .preview)
}
