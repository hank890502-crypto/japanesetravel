import SwiftUI

/// 本桌訂單：每道菜的總數、誰點的、金額。可以整份「給店員看」。
struct OrderSummaryView: View {
    @Environment(AppRouter.self) private var router
    @Environment(DiningSessionStore.self) private var sessionStore
    @Environment(\.dependencies) private var dependencies

    @State private var viewModel: RoomViewModel?
    @State private var showStaffView = false

    var body: some View {
        Group {
            if let viewModel {
                content(viewModel)
            } else {
                Text("目前沒有在任何房間裡。")
                    .font(.app(.body))
                    .foregroundStyle(AppColors.secondaryText)
                    .padding()
            }
        }
        .elderlyScreen(title: "本桌訂單")
        .onAppear {
            if viewModel == nil, let session = sessionStore.current {
                let vm = RoomViewModel(session: session, roomRepository: dependencies.roomRepository, menuRepository: dependencies.menuRepository, orderRepository: dependencies.orderRepository)
                vm.start()
                viewModel = vm
            }
        }
        .onDisappear {
            viewModel?.stop()
            viewModel = nil
        }
        .fullScreenCover(isPresented: $showStaffView) {
            if let viewModel {
                StaffOrderView(lines: viewModel.summaryLines, roomName: viewModel.room.name) { showStaffView = false }
            }
        }
    }

    private func content(_ viewModel: RoomViewModel) -> some View {
        let lines = viewModel.summaryLines
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let error = viewModel.error {
                    ErrorBanner(error: error)
                }

                if lines.isEmpty {
                    Text("還沒有人點東西。回到菜單按「+」就會出現在這裡。")
                        .font(.app(.body))
                        .foregroundStyle(AppColors.secondaryText)
                } else {
                    Text("\(viewModel.members.count) 個人一起點的。每道菜下面是誰點的。")
                        .font(.app(.body))
                        .foregroundStyle(AppColors.secondaryText)

                    ForEach(lines) { line in
                        lineCard(line, viewModel)
                    }
                }
            }
            .padding(AccessibilityMetrics.screenPadding)
            .padding(.bottom, 24)
        }
        .safeAreaInset(edge: .bottom) {
            if !lines.isEmpty {
                totalBar(viewModel)
            }
        }
    }

    /// 底部固定：總份數、總金額、我的小計、給店員看。
    private func totalBar(_ viewModel: RoomViewModel) -> some View {
        VStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("總共 \(viewModel.totalQuantity) 份")
                    .font(.app(.sectionTitle))
                Spacer()
                if let total = viewModel.totalPrice, let text = PriceFormatter.string(total) {
                    Text(text)
                        .font(.system(.title, design: .rounded, weight: .bold))
                } else {
                    Text("有些菜沒有價格")
                        .font(.app(.caption))
                        .foregroundStyle(AppColors.secondaryText)
                }
            }
            if viewModel.myTotalQuantity > 0 {
                HStack {
                    Text("我點的 \(viewModel.myTotalQuantity) 份")
                        .font(.app(.body))
                        .foregroundStyle(AppColors.secondaryText)
                    Spacer()
                    if let mine = viewModel.myTotalPrice, let text = PriceFormatter.string(mine) {
                        Text(text)
                            .font(.app(.body).weight(.semibold))
                            .foregroundStyle(AppColors.secondaryText)
                    }
                }
            }
            PrimaryButton(title: "給店員看", systemImage: AppIcon.showToStaff) {
                showStaffView = true
            }
        }
        .padding(.horizontal, AccessibilityMetrics.screenPadding)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(AppColors.cardBackground.opacity(0.97))
        .overlay(alignment: .top) { Rectangle().fill(AppColors.separator).frame(height: 1) }
        .accessibilityElement(children: .combine)
    }

    private func lineCard(_ line: OrderSummaryLine, _ viewModel: RoomViewModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(line.staffDisplayName)
                        .font(.app(.japanese))
                        .foregroundStyle(AppColors.primaryText)
                    if let reading = viewModel.reading(for: line.menuItem) {
                        Text(reading)
                            .font(.system(.subheadline, design: .rounded).italic())
                            .foregroundStyle(AppColors.secondaryText)
                    }
                    Text([line.menuItem.chineseName, line.options.isEmpty ? nil : line.options.map(\.displayName).joined(separator: "・")].compactMap { $0 }.joined(separator: "，"))
                        .font(.app(.body))
                        .foregroundStyle(AppColors.secondaryText)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("×\(line.totalQuantity)")
                        .font(.system(.title, design: .rounded, weight: .bold))
                    if let subtotal = line.subtotal, let text = PriceFormatter.string(subtotal) {
                        Text(text)
                            .font(.app(.body))
                            .foregroundStyle(AppColors.secondaryText)
                    }
                }
            }
            Text(line.byMember.map { "\($0.member.displayName) \($0.quantity)" }.joined(separator: "　"))
                .font(.app(.caption))
                .foregroundStyle(AppColors.secondaryText)
        }
        .padding(AccessibilityMetrics.screenPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: AccessibilityMetrics.cornerRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// 給店員看的整桌訂單：白底、大日文、數量。
struct StaffOrderView: View {
    let lines: [OrderSummaryLine]
    let roomName: String
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("注文（\(OrderSummaryBuilder.totalQuantity(of: lines))点）")
                    .font(.system(.title2, weight: .bold))
                    .foregroundStyle(.black)
                Spacer()
                Button(action: onClose) {
                    HStack(spacing: 6) {
                        Image(systemName: AppIcon.close)
                        Text("關閉")
                    }
                    .font(.app(.buttonLabel))
                    .foregroundStyle(.black)
                    .frame(minHeight: AccessibilityMetrics.minimumTapTarget)
                    .padding(.horizontal, 20)
                    .background(Color(white: 0.92), in: Capsule())
                }
            }
            .padding(AccessibilityMetrics.screenPadding)

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(lines) { line in
                        HStack(alignment: .firstTextBaseline, spacing: 16) {
                            Text(line.staffDisplayName)
                                .font(.system(.title, weight: .bold))
                                .foregroundStyle(.black)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text("× \(line.totalQuantity)")
                                .font(.system(.largeTitle, design: .rounded, weight: .heavy))
                                .foregroundStyle(.black)
                        }
                        .padding(.vertical, 16)
                        .padding(.horizontal, AccessibilityMetrics.screenPadding)
                        Divider().background(Color(white: 0.8))
                    }
                }
            }
        }
        .background(Color.white.ignoresSafeArea())
        .preferredColorScheme(.light)
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }
}

#Preview {
    NavigationStack { OrderSummaryView() }
        .environment(AppRouter())
        .environment(DiningSessionStore(defaults: UserDefaults(suiteName: "preview")!))
        .environment(\.dependencies, .preview)
}
