import SwiftUI

/// 語意化顏色。只用系統色，自動支援深色模式與高對比。
/// 原則：狀態不能只靠顏色表達，一定搭配 icon 或文字。
enum AppColors {
    static let screenBackground = Color(uiColor: .systemGroupedBackground)
    static let cardBackground = Color(uiColor: .secondarySystemGroupedBackground)
    static let primaryText = Color.primary
    static let secondaryText = Color.secondary
    static let separator = Color(uiColor: .separator)

    static let accent = Color.accentColor
    static let error = Color(uiColor: .systemRed)
    static let errorBackground = Color(uiColor: .systemRed).opacity(0.12)
    static let success = Color(uiColor: .systemGreen)

    // 首頁四大入口的識別色（只用在 icon 底色，文字一律用 primaryText）
    static let talk = Color(uiColor: .systemBlue)
    static let understand = Color(uiColor: .systemOrange)
    static let go = Color(uiColor: .systemGreen)
    static let help = Color(uiColor: .systemRed)
}
