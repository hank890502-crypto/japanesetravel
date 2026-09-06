import SwiftUI

/// 每一頁統一的頂部列：大字「上一頁」+ 頁面標題。取代系統導覽列（太小、太淡）。
struct ElderlyNavigationBar: View {
    let title: String
    var showsBack: Bool = true
    var trailing: AnyView? = nil

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if showsBack {
                    Button {
                        dismiss()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: AppIcon.back)
                                .font(.system(.title3, weight: .bold))
                            Text("上一頁")
                                .font(.app(.buttonLabel))
                        }
                        .foregroundStyle(AppColors.accent)
                        .frame(minHeight: AccessibilityMetrics.minimumTapTarget)
                        .padding(.trailing, 12)
                        .contentShape(Rectangle())
                    }
                    .accessibilityLabel("回到上一頁")
                }
                Spacer()
                if let trailing {
                    trailing
                }
            }
            Text(title)
                .font(.app(.screenTitle))
                .foregroundStyle(AppColors.primaryText)
                .accessibilityAddTraits(.isHeader)
        }
        .padding(.horizontal, AccessibilityMetrics.screenPadding)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }
}

/// 套在每個 pushed 畫面上：隱藏系統導覽列、加上長輩版頂部列、統一背景。
struct ElderlyScreenModifier: ViewModifier {
    let title: String
    let showsBack: Bool

    func body(content: Content) -> some View {
        VStack(spacing: 0) {
            ElderlyNavigationBar(title: title, showsBack: showsBack)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .readableWidth()
        .background(AppColors.screenBackground.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
    }
}

extension View {
    func elderlyScreen(title: String, showsBack: Bool = true) -> some View {
        modifier(ElderlyScreenModifier(title: title, showsBack: showsBack))
    }
}

#Preview {
    NavigationStack {
        ScrollView {
            Text("內容")
                .font(.app(.body))
                .padding()
        }
        .elderlyScreen(title: "我要跟人說話")
    }
}
