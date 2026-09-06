import SwiftUI

/// 修改／新增一道菜：三個大欄位（日文、中文、價格），儲存、刪除、取消。
struct MenuItemEditorView: View {
    @State private var item: MenuItemDraft
    let isNew: Bool
    let availableSections: [String]
    let onSave: (MenuItemDraft) -> Void
    let onDelete: () -> Void
    let onCancel: () -> Void

    @FocusState private var focusedField: Field?
    @State private var confirmDelete = false
    @State private var showSectionChoices = false
    @State private var isAddingSection = false
    @State private var newSectionName = ""
    @State private var newOption = MenuOptionDraft(groupName: "", japaneseName: "")
    @State private var isAddingOption = false

    private enum Field { case japanese, chinese, price, newSection, optionGroup, optionJapanese, optionChinese, optionDelta }

    init(item: MenuItemDraft, isNew: Bool, availableSections: [String] = [], onSave: @escaping (MenuItemDraft) -> Void, onDelete: @escaping () -> Void, onCancel: @escaping () -> Void) {
        _item = State(initialValue: item)
        self.isNew = isNew
        self.availableSections = availableSections
        self.onSave = onSave
        self.onDelete = onDelete
        self.onCancel = onCancel
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Button("取消", action: onCancel)
                        .font(.app(.buttonLabel))
                        .frame(minHeight: AccessibilityMetrics.minimumTapTarget)
                    Spacer()
                }
                Text(isNew ? "新增一道菜" : "修改這道菜")
                    .font(.app(.screenTitle))
                    .accessibilityAddTraits(.isHeader)

                if let ocrText = item.ocrText?.nilIfBlank {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("照片上辨識到的是：")
                            .font(.app(.caption))
                            .foregroundStyle(AppColors.secondaryText)
                        Text(ocrText)
                            .font(.app(.body))
                            .foregroundStyle(AppColors.primaryText)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }

                field(label: "日文名稱（菜單上的字）", text: $item.japaneseName, placeholder: "例如：若どり唐揚げ", focus: .japanese)
                field(label: "中文（可以不填）", text: $item.chineseName, placeholder: "例如：炸嫩雞", focus: .chinese)
                field(label: "價格（日圓，只填數字）", text: $item.priceText, placeholder: "例如：540", focus: .price, keyboard: .numberPad)

                sectionField

                optionsField

                PrimaryButton(title: "儲存", systemImage: AppIcon.check, isEnabled: item.isValid) {
                    onSave(item)
                }

                if !isNew {
                    Button(role: .destructive) {
                        confirmDelete = true
                    } label: {
                        Label("刪除這道菜", systemImage: AppIcon.delete)
                            .font(.app(.buttonLabel))
                            .foregroundStyle(AppColors.error)
                            .elderlyTapTarget()
                    }
                    .confirmationDialog("確定要刪除這道菜嗎？", isPresented: $confirmDelete, titleVisibility: .visible) {
                        Button("刪除", role: .destructive, action: onDelete)
                        Button("不要刪除", role: .cancel) {}
                    }
                }
            }
            .padding(AccessibilityMetrics.screenPadding)
        }
        .background(AppColors.screenBackground.ignoresSafeArea())
        .scrollDismissesKeyboard(.interactively)
        .onAppear {
            if isNew { focusedField = .japanese }
        }
    }

    /// 分類：按一下跳出現有分類清單，或新增一個。
    private var sectionField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("分類（可以不選）")
                .font(.app(.body))
                .foregroundStyle(AppColors.secondaryText)
            Button {
                showSectionChoices = true
            } label: {
                HStack {
                    Text(item.sectionName?.nilIfBlank ?? "沒有分類")
                        .font(.app(.sectionTitle))
                        .foregroundStyle(item.sectionName?.nilIfBlank == nil ? AppColors.secondaryText : AppColors.primaryText)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .foregroundStyle(AppColors.accent)
                }
                .padding(16)
                .frame(minHeight: AccessibilityMetrics.minimumTapTarget)
                .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(AppColors.separator, lineWidth: 2))
            }
            .accessibilityLabel("分類，目前是 \(item.sectionName?.nilIfBlank ?? "沒有分類")")
            .confirmationDialog("選擇分類", isPresented: $showSectionChoices, titleVisibility: .visible) {
                ForEach(availableSections, id: \.self) { section in
                    Button(section) { item.sectionName = section }
                }
                Button("新增分類…") {
                    isAddingSection = true
                    focusedField = .newSection
                }
                Button("沒有分類") { item.sectionName = nil }
                Button("取消", role: .cancel) {}
            }
            if isAddingSection {
                HStack(spacing: 8) {
                    TextField("新分類的名稱，例如：飲料", text: $newSectionName)
                        .font(.app(.body))
                        .focused($focusedField, equals: .newSection)
                        .padding(12)
                        .frame(minHeight: AccessibilityMetrics.minimumTapTarget)
                        .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    Button("確定") {
                        if let name = newSectionName.nilIfBlank { item.sectionName = name }
                        newSectionName = ""
                        isAddingSection = false
                    }
                    .font(.app(.buttonLabel))
                    .frame(minHeight: AccessibilityMetrics.minimumTapTarget)
                }
            }
        }
    }

    /// 選項：份量、套餐升級、配料。每列可刪，可新增。
    private var optionsField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("選項（份量、套餐、加價升級，可以不填）")
                .font(.app(.body))
                .foregroundStyle(AppColors.secondaryText)

            ForEach(item.options) { option in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(option.groupName)：\(option.japaneseName)")
                            .font(.app(.body))
                            .foregroundStyle(AppColors.primaryText)
                        Text(option.displayText)
                            .font(.app(.caption))
                            .foregroundStyle(AppColors.secondaryText)
                    }
                    Spacer()
                    Button {
                        item.options.removeAll { $0.id == option.id }
                    } label: {
                        Image(systemName: AppIcon.delete)
                            .font(.app(.buttonLabel))
                            .foregroundStyle(AppColors.error)
                            .frame(width: AccessibilityMetrics.minimumTapTarget, height: AccessibilityMetrics.minimumTapTarget)
                    }
                    .accessibilityLabel("刪除選項 \(option.japaneseName)")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            if isAddingOption {
                VStack(spacing: 10) {
                    smallField("群組（例如 份量、套餐）", text: $newOption.groupName, focus: .optionGroup)
                    smallField("日文選項（菜單上的字，例如 大盛り）", text: $newOption.japaneseName, focus: .optionJapanese)
                    smallField("中文（例如 大份）", text: $newOption.chineseName, focus: .optionChinese)
                    smallField("價差（例如 +150、-100、0）", text: $newOption.priceDeltaText, focus: .optionDelta, keyboard: .numbersAndPunctuation)
                    HStack(spacing: 12) {
                        SecondaryButton(title: "取消") {
                            isAddingOption = false
                            newOption = MenuOptionDraft(groupName: "", japaneseName: "")
                        }
                        PrimaryButton(title: "加入選項", isEnabled: newOption.isValid) {
                            item.options.append(newOption)
                            newOption = MenuOptionDraft(groupName: newOption.groupName, japaneseName: "")
                            focusedField = .optionJapanese
                        }
                    }
                }
                .padding(12)
                .background(AppColors.cardBackground.opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                Button {
                    isAddingOption = true
                    focusedField = .optionGroup
                } label: {
                    Label("新增選項", systemImage: AppIcon.add)
                        .font(.app(.buttonLabel))
                        .foregroundStyle(AppColors.accent)
                        .frame(minHeight: AccessibilityMetrics.minimumTapTarget)
                }
            }
        }
    }

    private func smallField(_ placeholder: String, text: Binding<String>, focus: Field, keyboard: UIKeyboardType = .default) -> some View {
        TextField(placeholder, text: text)
            .font(.app(.body))
            .keyboardType(keyboard)
            .focused($focusedField, equals: focus)
            .padding(12)
            .frame(minHeight: AccessibilityMetrics.minimumTapTarget)
            .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(focusedField == focus ? AppColors.accent : AppColors.separator, lineWidth: 2))
    }

    private func field(label: String, text: Binding<String>, placeholder: String, focus: Field, keyboard: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.app(.body))
                .foregroundStyle(AppColors.secondaryText)
            TextField(placeholder, text: text)
                .font(.app(.sectionTitle))
                .keyboardType(keyboard)
                .focused($focusedField, equals: focus)
                .padding(16)
                .frame(minHeight: AccessibilityMetrics.minimumTapTarget)
                .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(focusedField == focus ? AppColors.accent : AppColors.separator, lineWidth: 2)
                )
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview("修改") {
    MenuItemEditorView(
        item: MenuItemDraft(japaneseName: "とんかつ", chineseName: "炸豬排", priceText: "540", ocrText: "とんかつ ¥540", sectionName: "揚げ物", options: [
            MenuOptionDraft(groupName: "份量", japaneseName: "大盛り", chineseName: "大份", priceDeltaText: "+150"),
            MenuOptionDraft(groupName: "套餐", japaneseName: "定食セット", chineseName: "升級定食", priceDeltaText: "+300"),
        ]),
        isNew: false,
        availableSections: ["揚げ物", "焼き物", "ドリンク"],
        onSave: { _ in }, onDelete: {}, onCancel: {}
    )
}

#Preview("新增") {
    MenuItemEditorView(item: MenuItemDraft(japaneseName: ""), isNew: true, onSave: { _ in }, onDelete: {}, onCancel: {})
}
