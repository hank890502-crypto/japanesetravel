import SwiftUI

/// 首頁：只有四個大入口。不出現任何技術詞。
struct HomeView: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("日本旅遊助手")
                            .font(.app(.screenTitle))
                            .foregroundStyle(AppColors.primaryText)
                            .accessibilityAddTraits(.isHeader)
                        Text("請問你現在想做什麼？")
                            .font(.app(.body))
                            .foregroundStyle(AppColors.secondaryText)
                    }
                    Spacer()
                    Button {
                        router.push(.settings)
                    } label: {
                        VStack(spacing: 2) {
                            Image(systemName: "gearshape.fill")
                                .font(.system(.title2, weight: .semibold))
                            Text("設定")
                                .font(.system(.caption, weight: .semibold))
                        }
                        .foregroundStyle(AppColors.secondaryText)
                        .frame(width: AccessibilityMetrics.minimumTapTarget, height: AccessibilityMetrics.minimumTapTarget)
                    }
                    .accessibilityLabel("設定")
                }
                .padding(.bottom, 8)

                ForEach(HomeEntry.allCases) { entry in
                    LargeActionCard(
                        title: entry.title,
                        subtitle: entry.subtitle,
                        systemImage: entry.systemImage,
                        tint: entry.tint
                    ) {
                        router.push(entry.route)
                    }
                }
            }
            .padding(AccessibilityMetrics.screenPadding)
            .readableWidth()
        }
        .background(AppColors.screenBackground.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }
}

/// 首頁四大入口。
enum HomeEntry: CaseIterable, Identifiable {
    case talk
    case understand
    case go
    case help

    var id: Self { self }

    var title: String {
        switch self {
        case .talk: "我要跟人說話"
        case .understand: "我要看懂這個"
        case .go: "我要去一個地方"
        case .help: "我遇到問題"
        }
    }

    var subtitle: String {
        switch self {
        case .talk: "飯店、租車、餐廳、購物常用的話"
        case .understand: "菜單、商品、價牌，一家人一起點餐"
        case .go: "用地圖帶我去"
        case .help: "求助、找醫院、找警察"
        }
    }

    var systemImage: String {
        switch self {
        case .talk: AppIcon.talk
        case .understand: AppIcon.understand
        case .go: AppIcon.go
        case .help: AppIcon.help
        }
    }

    var tint: Color {
        switch self {
        case .talk: AppColors.talk
        case .understand: AppColors.understand
        case .go: AppColors.go
        case .help: AppColors.help
        }
    }

    var route: Route {
        switch self {
        case .talk: .communicationCategories
        case .understand: .understandHub
        case .go: .places
        case .help: .emergency
        }
    }
}

#Preview("首頁") {
    NavigationStack {
        HomeView()
    }
    .environment(AppRouter())
    .environment(\.dependencies, .preview)
}

#Preview("首頁 超大字體") {
    NavigationStack {
        HomeView()
    }
    .environment(AppRouter())
    .environment(\.dependencies, .preview)
    .dynamicTypeSize(.accessibility2)
}
