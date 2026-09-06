import SwiftUI

/// 長輩版的尺寸基準。Apple 建議最小 44pt，我們用更大的值。
enum AccessibilityMetrics {
    /// 所有可點擊元件的最小高度
    static let minimumTapTarget: CGFloat = 60
    /// 大卡片的最小高度
    static let largeCardMinHeight: CGFloat = 104
    static let cornerRadius: CGFloat = 20
    static let screenPadding: CGFloat = 20
    /// iPad 上內容的最大寬度，超過就置中留白，卡片才不會太寬
    static let maxContentWidth: CGFloat = 720
}

extension View {
    /// 把內容限制在 maxContentWidth 並置中（iPhone 上沒有影響）。
    func readableWidth() -> some View {
        frame(maxWidth: AccessibilityMetrics.maxContentWidth)
            .frame(maxWidth: .infinity)
    }
}

extension View {
    /// 保證最小可點擊高度並撐滿寬度。
    func elderlyTapTarget() -> some View {
        frame(maxWidth: .infinity, minHeight: AccessibilityMetrics.minimumTapTarget)
            .contentShape(Rectangle())
    }
}
