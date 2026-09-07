import SwiftUI

/// 選一道菜的分類：App 內的大卡片清單（不用系統選單，分類多也不會變成一長串小字），
/// 最下面可以新增分類。選了就關閉。
struct MenuSectionPickerSheet: View {
    let sections: [String]
    /// 日文分類 → 中文，有的話顯示在副標
    var chineseNames: [String: String] = [:]
    let selected: String?
    /// nil = 沒有分類
    let onSelect: (String?) -> Void
    let onClose: () -> Void

    @State private var isAddingSection = false
    @State private var newSectionName = ""
    @FocusState private var newSectionFocused: Bool

    /// 目前選的分類如果不在清單裡（剛新增的），也列出來
    private var allSections: [String] {
        if let selected = selected?.nilIfBlank, !sections.contains(selected) { return sections + [selected] }
        return sections
    }

    var body: some View {
        // 包在 NavigationStack 裡（導覽列隱藏）：鍵盤上方的「完成」工具列只有在 NavigationStack 內才會顯示
        NavigationStack {
            picker
                .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var picker: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                Text("選擇分類")
                    .font(.app(.screenTitle))
                    .foregroundStyle(AppColors.primaryText)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button(action: onClose) {
                    HStack(spacing: 6) {
                        Image(systemName: AppIcon.close)
                        Text("關閉")
                    }
                    .font(.app(.buttonLabel))
                    .foregroundStyle(AppColors.accent)
                    .frame(minHeight: AccessibilityMetrics.minimumTapTarget)
                    .padding(.horizontal, 16)
                    .background(AppColors.cardBackground, in: Capsule())
                }
                .accessibilityLabel("關閉，不改分類")
            }
            .padding(AccessibilityMetrics.screenPadding)
            .padding(.top, 12)   // 導覽列隱藏後內容會貼到 sheet 頂端，留一點空間

            ScrollView {
                VStack(spacing: 12) {
                    ChoiceCard(title: "沒有分類", subtitle: "這道菜不放在任何分類裡", isSelected: selected?.nilIfBlank == nil) {
                        onSelect(nil)
                    }
                    ForEach(allSections, id: \.self) { section in
                        ChoiceCard(title: section, subtitle: chineseNames[section], isSelected: selected == section) {
                            onSelect(section)
                        }
                    }

                    if isAddingSection {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("新分類的名稱（照菜單上的字，或用中文都可以）")
                                .font(.app(.body))
                                .foregroundStyle(AppColors.secondaryText)
                            TextField("例如：ドリンク 或 飲料", text: $newSectionName)
                                .font(.app(.sectionTitle))
                                .focused($newSectionFocused)
                                .submitLabel(.done)
                                .onSubmit(addSection)
                                .padding(16)
                                .frame(minHeight: AccessibilityMetrics.minimumTapTarget)
                                .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(newSectionFocused ? AppColors.accent : AppColors.separator, lineWidth: 2))
                            HStack(spacing: 12) {
                                SecondaryButton(title: "取消") {
                                    isAddingSection = false
                                    newSectionName = ""
                                }
                                PrimaryButton(title: "加入", systemImage: AppIcon.check, isEnabled: newSectionName.nilIfBlank != nil) {
                                    addSection()
                                }
                            }
                        }
                        .padding(AccessibilityMetrics.screenPadding)
                        .background(AppColors.cardBackground.opacity(0.6), in: RoundedRectangle(cornerRadius: AccessibilityMetrics.cornerRadius, style: .continuous))
                    } else {
                        Button {
                            isAddingSection = true
                            newSectionFocused = true
                        } label: {
                            Label("新增分類…", systemImage: AppIcon.add)
                                .font(.app(.cardTitle))
                                .foregroundStyle(AppColors.accent)
                                .padding(AccessibilityMetrics.screenPadding)
                                .frame(maxWidth: .infinity, minHeight: AccessibilityMetrics.minimumTapTarget, alignment: .leading)
                                .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: AccessibilityMetrics.cornerRadius, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: AccessibilityMetrics.cornerRadius, style: .continuous).strokeBorder(AppColors.accent, style: StrokeStyle(lineWidth: 2, dash: [8, 6])))
                        }
                        .buttonStyle(CardPressStyle())
                        .accessibilityLabel("新增分類")
                    }
                }
                .padding(.horizontal, AccessibilityMetrics.screenPadding)
                .padding(.bottom, AccessibilityMetrics.screenPadding)
                .readableWidth()
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(AppColors.screenBackground.ignoresSafeArea())
        .keyboardDoneButton { newSectionFocused = false }
    }

    private func addSection() {
        guard let name = newSectionName.nilIfBlank else { return }
        onSelect(name)
    }
}

#Preview {
    MenuSectionPickerSheet(
        sections: ["揚げ物", "焼き物", "ドリンク", "サラダ", "ご飯もの", "麺類", "デザート"],
        chineseNames: ["揚げ物": "炸物", "ドリンク": "飲料", "デザート": "甜點"],
        selected: "揚げ物",
        onSelect: { _ in },
        onClose: {}
    )
}
