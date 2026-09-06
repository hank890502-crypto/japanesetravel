import SwiftUI

/// 白話錯誤提示：icon + 標題 + 說明 + 可選的「再試一次」。不只靠顏色表達。
struct ErrorBanner: View {
    let error: UserFacingError
    var retry: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: AppIcon.warning)
                    .font(.app(.cardTitle))
                    .foregroundStyle(AppColors.error)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(error.title)
                        .font(.app(.cardTitle))
                        .foregroundStyle(AppColors.primaryText)
                    Text(error.message)
                        .font(.app(.body))
                        .foregroundStyle(AppColors.primaryText)
                }
            }
            if let retry, error.isRetryable {
                SecondaryButton(title: "再試一次", systemImage: AppIcon.retry, action: retry)
            }
        }
        .padding(AccessibilityMetrics.screenPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.errorBackground, in: RoundedRectangle(cornerRadius: AccessibilityMetrics.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AccessibilityMetrics.cornerRadius, style: .continuous)
                .strokeBorder(AppColors.error.opacity(0.5), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    VStack(spacing: 16) {
        ErrorBanner(error: .syncUnavailable) {}
        ErrorBanner(error: .aiNotEnabled)
    }
    .padding()
    .background(AppColors.screenBackground)
}
