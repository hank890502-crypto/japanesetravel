import SwiftUI

/// 大顆的 − 數字 +。數量 0 時只顯示「+ 點這個」。
struct QuantityStepper: View {
    let quantity: Int
    let onDecrement: () -> Void
    let onIncrement: () -> Void
    var addTitle: String = "點"

    var body: some View {
        HStack(spacing: 0) {
            if quantity > 0 {
                stepButton(systemImage: "minus", label: "減少一份", action: onDecrement)
                Text("\(quantity)")
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .foregroundStyle(AppColors.primaryText)
                    .frame(minWidth: 44)
                    .accessibilityLabel("\(quantity) 份")
                stepButton(systemImage: "plus", label: "增加一份", action: onIncrement)
            } else {
                Button(action: onIncrement) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                        Text(addTitle)
                    }
                    .font(.app(.buttonLabel))
                    .foregroundStyle(.white)
                    .frame(minWidth: 88, minHeight: AccessibilityMetrics.minimumTapTarget - 8)
                    .padding(.horizontal, 12)
                    .background(AppColors.accent, in: Capsule())
                }
                .buttonStyle(CardPressStyle())
                .accessibilityLabel("\(addTitle)一份")
            }
        }
    }

    private func stepButton(systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(.title3, weight: .bold))
                .foregroundStyle(AppColors.accent)
                .frame(width: AccessibilityMetrics.minimumTapTarget - 8, height: AccessibilityMetrics.minimumTapTarget - 8)
                .background(AppColors.accent.opacity(0.12), in: Circle())
        }
        .buttonStyle(CardPressStyle())
        .accessibilityLabel(label)
    }
}

#Preview {
    VStack(spacing: 20) {
        QuantityStepper(quantity: 0, onDecrement: {}, onIncrement: {})
        QuantityStepper(quantity: 2, onDecrement: {}, onIncrement: {})
    }
    .padding()
}
