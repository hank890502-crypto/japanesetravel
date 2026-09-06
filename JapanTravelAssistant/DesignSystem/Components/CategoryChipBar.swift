import SwiftUI

/// 橫向的分類按鈕列：大顆、可捲、選中的實心。
struct CategoryChipBar: View {
    struct Chip: Identifiable, Hashable {
        var id: String
        var title: String
        var subtitle: String?
        /// 例如「我點了 2 份」→ 顯示小數字
        var badge: Int = 0
    }

    let chips: [Chip]
    @Binding var selectedId: String

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(chips) { chip in
                        chipView(chip)
                            .id(chip.id)
                    }
                }
                .padding(.horizontal, AccessibilityMetrics.screenPadding)
                .padding(.vertical, 10)
            }
            .onChange(of: selectedId) { _, newValue in
                withAnimation { proxy.scrollTo(newValue, anchor: .center) }
            }
        }
        .background(AppColors.screenBackground)
    }

    private func chipView(_ chip: Chip) -> some View {
        let isSelected = chip.id == selectedId
        return Button {
            withAnimation(.easeOut(duration: 0.15)) { selectedId = chip.id }
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(chip.title)
                        .font(.app(.buttonLabel))
                    if let subtitle = chip.subtitle?.nilIfBlank {
                        Text(subtitle)
                            .font(.system(.caption, weight: .semibold))
                            .opacity(0.85)
                    }
                }
                if chip.badge > 0 {
                    Text("\(chip.badge)")
                        .font(.system(.caption, weight: .bold))
                        .foregroundStyle(isSelected ? AppColors.accent : .white)
                        .frame(minWidth: 22, minHeight: 22)
                        .background(isSelected ? Color.white : AppColors.accent, in: Capsule())
                }
            }
            .foregroundStyle(isSelected ? .white : AppColors.primaryText)
            .padding(.horizontal, 16)
            .frame(minHeight: AccessibilityMetrics.minimumTapTarget)
            .background(isSelected ? AppColors.accent : AppColors.cardBackground, in: Capsule())
            .overlay(Capsule().strokeBorder(isSelected ? .clear : AppColors.separator, lineWidth: 1))
        }
        .buttonStyle(CardPressStyle())
        .accessibilityLabel("\(chip.title)\(chip.subtitle.map { "，\($0)" } ?? "")\(chip.badge > 0 ? "，我點了 \(chip.badge) 份" : "")")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

#Preview {
    struct Demo: View {
        @State private var selected = "all"
        var body: some View {
            CategoryChipBar(chips: [
                .init(id: "all", title: "全部"),
                .init(id: "1", title: "揚げ物", subtitle: "炸物", badge: 2),
                .init(id: "2", title: "焼き物", subtitle: "烤物"),
                .init(id: "3", title: "ドリンク", subtitle: "飲料"),
            ], selectedId: $selected)
        }
    }
    return Demo()
}
