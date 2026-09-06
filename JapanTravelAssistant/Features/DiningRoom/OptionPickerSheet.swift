import SwiftUI

/// 有選項的菜：每個群組選一個（可以不選），看到價格，按「加一份」。
struct OptionPickerSheet: View {
    let item: MenuItem
    let options: [MenuItemOption]
    var reading: String? = nil
    let onAdd: ([UUID]) -> Void
    let onCancel: () -> Void

    @State private var chosen: [String: UUID] = [:]   // 群組 → 選項 id

    private var groups: [(group: String, options: [MenuItemOption])] { options.groupedByName }
    private var chosenIds: [UUID] { groups.compactMap { chosen[$0.group] } }
    private var unitPrice: Decimal? {
        guard let base = item.price else { return nil }
        let deltas = chosenIds.compactMap { id in options.first { $0.id == id }?.priceDelta }
        return base + deltas.reduce(Decimal(0), +)
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
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.displayName)
                        .font(.app(.screenTitle))
                    if item.chineseName != nil {
                        Text(item.japaneseName)
                            .font(.app(.japanese))
                            .foregroundStyle(AppColors.secondaryText)
                    }
                    if let reading {
                        Text(reading)
                            .font(.system(.subheadline, design: .rounded).italic())
                            .foregroundStyle(AppColors.secondaryText)
                    }
                }

                ForEach(groups, id: \.group) { group in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(group.group)
                            .font(.app(.sectionTitle))
                        choiceRow(title: "不用", subtitle: nil, delta: nil, isSelected: chosen[group.group] == nil) {
                            chosen[group.group] = nil
                        }
                        ForEach(group.options) { option in
                            choiceRow(
                                title: option.displayName,
                                subtitle: option.nameChinese == nil ? nil : option.nameJapanese,
                                delta: option.priceDeltaText,
                                isSelected: chosen[group.group] == option.id
                            ) {
                                chosen[group.group] = option.id
                            }
                        }
                    }
                }

                PrimaryButton(
                    title: unitPrice.flatMap { PriceFormatter.string($0) }.map { "加一份（\($0)）" } ?? "加一份",
                    systemImage: "plus"
                ) {
                    onAdd(chosenIds)
                }
            }
            .padding(AccessibilityMetrics.screenPadding)
        }
        .background(AppColors.screenBackground.ignoresSafeArea())
    }

    private func choiceRow(title: String, subtitle: String?, delta: String?, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(.title2, weight: .semibold))
                    .foregroundStyle(isSelected ? AppColors.accent : AppColors.secondaryText)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.app(.body).weight(.semibold))
                        .foregroundStyle(AppColors.primaryText)
                    if let subtitle {
                        Text(subtitle)
                            .font(.app(.caption))
                            .foregroundStyle(AppColors.secondaryText)
                    }
                }
                Spacer()
                if let delta {
                    Text(delta)
                        .font(.app(.body).weight(.semibold))
                        .foregroundStyle(AppColors.primaryText)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: AccessibilityMetrics.minimumTapTarget, alignment: .leading)
            .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(isSelected ? AppColors.accent : .clear, lineWidth: 2))
        }
        .buttonStyle(CardPressStyle())
        .accessibilityLabel("\(title)\(delta.map { "，\($0)" } ?? "")")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

#Preview {
    let itemId = UUID()
    return OptionPickerSheet(
        item: MenuItem(menuId: UUID(), japaneseName: "とんかつ", chineseName: "炸豬排", reading: "tonkatsu", price: 540),
        options: [
            MenuItemOption(menuItemId: itemId, groupName: "份量", nameJapanese: "大盛り", nameChinese: "大份", priceDelta: 150, sortOrder: 0),
            MenuItemOption(menuItemId: itemId, groupName: "套餐", nameJapanese: "定食セット", nameChinese: "升級定食", priceDelta: 300, sortOrder: 1),
        ],
        onAdd: { _ in }, onCancel: {}
    )
}
