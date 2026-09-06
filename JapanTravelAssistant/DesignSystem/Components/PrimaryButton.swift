import SwiftUI

/// 主要動作按鈕：滿版、高、實心。每頁最多一個。
struct PrimaryButton: View {
    let title: String
    var systemImage: String? = nil
    var isLoading: Bool = false
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if isLoading {
                    ProgressView().tint(.white)
                } else if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
            }
            .font(.app(.buttonLabel))
            .foregroundStyle(.white)
            .elderlyTapTarget()
            .padding(.horizontal, 16)
            .background(
                (isEnabled ? AppColors.accent : AppColors.secondaryText),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
        }
        .buttonStyle(CardPressStyle())
        .disabled(!isEnabled || isLoading)
        .accessibilityLabel(title)
    }
}

/// 次要動作按鈕：滿版、高、外框。
struct SecondaryButton: View {
    let title: String
    var systemImage: String? = nil
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
            }
            .font(.app(.buttonLabel))
            .foregroundStyle(isEnabled ? AppColors.accent : AppColors.secondaryText)
            .elderlyTapTarget()
            .padding(.horizontal, 16)
            .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(isEnabled ? AppColors.accent : AppColors.secondaryText, lineWidth: 2)
            )
        }
        .buttonStyle(CardPressStyle())
        .disabled(!isEnabled)
        .accessibilityLabel(title)
    }
}

#Preview {
    VStack(spacing: 16) {
        PrimaryButton(title: "建立共享菜單", systemImage: AppIcon.joinRoom) {}
        PrimaryButton(title: "處理中", isLoading: true) {}
        PrimaryButton(title: "無法使用", isEnabled: false) {}
        SecondaryButton(title: "從相簿選照片", systemImage: AppIcon.photoLibrary) {}
    }
    .padding()
    .background(AppColors.screenBackground)
}
