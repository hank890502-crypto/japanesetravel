import SwiftUI

/// 全 App 的字體階層。全部基於系統 text style，因此自動支援 Dynamic Type。
enum AppTextStyle {
    /// 頁面標題
    case screenTitle
    /// 區塊標題
    case sectionTitle
    /// 大卡片標題
    case cardTitle
    /// 大卡片副標
    case cardSubtitle
    /// 一般內文
    case body
    /// 按鈕文字
    case buttonLabel
    /// 給店員看的中文說明（小）
    case caption
    /// 日文（列表內）
    case japanese
}

extension Font {
    static func app(_ style: AppTextStyle) -> Font {
        switch style {
        case .screenTitle: .system(.largeTitle, design: .rounded, weight: .bold)
        case .sectionTitle: .system(.title2, design: .rounded, weight: .bold)
        case .cardTitle: .system(.title2, weight: .bold)
        case .cardSubtitle: .system(.body)
        case .body: .system(.title3)
        case .buttonLabel: .system(.title3, weight: .semibold)
        case .caption: .system(.body)
        case .japanese: .system(.title2, weight: .semibold)
        }
    }
}
