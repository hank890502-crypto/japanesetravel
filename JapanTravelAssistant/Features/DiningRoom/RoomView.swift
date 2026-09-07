import SwiftUI

/// 用餐房間：看菜單、+ / − 點餐、看誰在房間裡、分享代碼。房主與家人看的是同一個畫面。
///
/// 資料來源是 RoomSessionCoordinator 持有的那一份 RoomViewModel（整個房間只有一份）。
/// 這裡不在 onAppear / onDisappear 建立或清掉任何東西：全螢幕 cover 會讓底層畫面收到 onDisappear，
/// 若在那裡清狀態，cover 會變成空白、關掉後整頁重新載入。
struct RoomView: View {
    @Environment(AppRouter.self) private var router
    @Environment(DiningSessionStore.self) private var sessionStore
    @Environment(RoomSessionCoordinator.self) private var coordinator
    @Environment(\.dependencies) private var dependencies

    @State private var optionPickerItem: MenuItem?
    @State private var confirmLeave = false
    /// QR Code cover 讀這份快照，房間狀態在 cover 打開時改變也不會變成空白
    @State private var qrCodeRoom: DiningRoom?
    @State private var selectedGroupId = RoomView.allGroupsId

    @State private var didPickInitialGroup = false

    private static let allGroupsId = "__all__"

    var body: some View {
        Group {
            if let viewModel = coordinator.viewModel {
                content(viewModel)
            } else if let notice = coordinator.endedNotice {
                endedView(notice)
            } else if sessionStore.current != nil {
                enteringView
            } else {
                noRoomView
            }
        }
        .elderlyScreen(title: sessionStore.current?.room.name ?? "點餐")
        .fullScreenCover(item: $qrCodeRoom) { room in
            RoomQRCodeSheet(room: room, webGuestURL: dependencies.config.webGuestURL) { qrCodeRoom = nil }
        }
        .sheet(item: $optionPickerItem) { item in
            if let viewModel = coordinator.viewModel {
                OptionPickerSheet(item: item, options: viewModel.options(for: item), reading: viewModel.reading(for: item)) { optionIds in
                    Task { await viewModel.adjust(item: item, optionIds: optionIds, by: 1) }
                    optionPickerItem = nil
                } onCancel: {
                    optionPickerItem = nil
                }
            }
        }
    }

    private var noRoomView: some View {
        VStack(spacing: 16) {
            Text("目前沒有在任何房間裡。")
                .font(.app(.body))
                .foregroundStyle(AppColors.secondaryText)
            SecondaryButton(title: "回到餐廳") { router.popOrPush(.restaurantHub) }
        }
        .padding(AccessibilityMetrics.screenPadding)
    }

    /// session 剛設定好、ViewModel 還在準備的一瞬間
    private var enteringView: some View {
        HStack(spacing: 12) {
            ProgressView()
            Text("正在進入房間…").font(.app(.body)).foregroundStyle(AppColors.secondaryText)
        }
        .padding(AccessibilityMetrics.screenPadding)
    }

    private func endedView(_ notice: UserFacingError) -> some View {
        VStack(spacing: 20) {
            ErrorBanner(error: notice)
            PrimaryButton(title: "回到餐廳", systemImage: AppIcon.restaurant) {
                coordinator.dismissEndedNotice()
                router.popOrPush(.restaurantHub)
            }
        }
        .padding(AccessibilityMetrics.screenPadding)
    }

    private func content(_ viewModel: RoomViewModel) -> some View {
        let groups = viewModel.groupedItems
        let visibleGroups = selectedGroupId == Self.allGroupsId ? groups : groups.filter { $0.id == selectedGroupId }
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 16, pinnedViews: [.sectionHeaders]) {
                roomCodeCard(viewModel)
                membersRow(viewModel)

                if let error = viewModel.error {
                    ErrorBanner(error: error)
                }

                if !viewModel.hasLoadedMenu {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("正在載入菜單…").font(.app(.body)).foregroundStyle(AppColors.secondaryText)
                    }
                    .padding(.vertical, 20)
                } else if viewModel.items.isEmpty {
                    Text("這個房間還沒有菜單。")
                        .font(.app(.body))
                        .foregroundStyle(AppColors.secondaryText)
                } else {
                    Section {
                        Text("點「+」就是我要一份。每個人各自點，房主會看到全部。")
                            .font(.app(.body))
                            .foregroundStyle(AppColors.secondaryText)

                        ForEach(visibleGroups) { group in
                            if selectedGroupId == Self.allGroupsId {
                                sectionHeader(group)
                            }
                            ForEach(group.items) { item in
                                itemRow(item, viewModel)
                            }
                        }
                    } header: {
                        if groups.count > 1 {
                            CategoryChipBar(chips: chips(for: groups, viewModel), selectedId: $selectedGroupId)
                                .padding(.horizontal, -AccessibilityMetrics.screenPadding)
                        }
                    }
                }

                Button(role: .destructive) { confirmLeave = true } label: {
                    Label("離開這個房間", systemImage: "rectangle.portrait.and.arrow.right")
                        .font(.app(.caption))
                        .foregroundStyle(AppColors.secondaryText)
                        .frame(maxWidth: .infinity, minHeight: AccessibilityMetrics.minimumTapTarget)
                }
                .padding(.top, 8)
                .confirmationDialog("要離開這個房間嗎？", isPresented: $confirmLeave, titleVisibility: .visible) {
                    Button("離開", role: .destructive) {
                        coordinator.leave()
                        router.popOrPush(.restaurantHub)
                    }
                    Button("留下", role: .cancel) {}
                } message: {
                    Text("你點的東西會留著，之後用同一個代碼可以再回來。")
                }
            }
            .padding(.horizontal, AccessibilityMetrics.screenPadding)
            .padding(.bottom, 80)
        }
        .onChange(of: groups.map(\.id), initial: true) { _, ids in
            // 第一次載入菜單時預設選第一個分類；分類消失時退回全部
            if selectedGroupId != Self.allGroupsId, !ids.contains(selectedGroupId) {
                selectedGroupId = ids.first ?? Self.allGroupsId
            } else if selectedGroupId == Self.allGroupsId, ids.count > 1, !didPickInitialGroup {
                didPickInitialGroup = true
                selectedGroupId = ids[0]
            }
        }
        .safeAreaInset(edge: .bottom) {
            PrimaryButton(
                title: viewModel.totalQuantity == 0 ? "本桌訂單（還沒有人點）" : "本桌訂單（\(viewModel.totalQuantity) 份）",
                systemImage: "list.bullet.clipboard.fill"
            ) {
                router.push(.orderSummary)
            }
            .padding(.horizontal, AccessibilityMetrics.screenPadding)
            .padding(.vertical, 12)
            .background(AppColors.screenBackground.opacity(0.95))
        }
    }

    /// 分類按鈕：全部 + 每個分類（帶「我點了幾份」）
    private func chips(for groups: [RoomViewModel.SectionGroup], _ viewModel: RoomViewModel) -> [CategoryChipBar.Chip] {
        let all = CategoryChipBar.Chip(id: Self.allGroupsId, title: "全部", badge: viewModel.myTotalQuantity)
        return [all] + groups.map { group in
            let mine = group.items.reduce(0) { $0 + viewModel.mySelections(for: $1).reduce(0) { $0 + $1.quantity } }
            return CategoryChipBar.Chip(id: group.id, title: group.title, subtitle: group.subtitle, badge: mine)
        }
    }

    // MARK: - 區塊

    private func roomCodeCard(_ viewModel: RoomViewModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("房間代碼，唸給家人聽：")
                .font(.app(.caption))
                .foregroundStyle(AppColors.secondaryText)
            HStack(alignment: .center, spacing: 12) {
                Text(viewModel.room.roomCode)
                    .font(.system(.largeTitle, design: .monospaced, weight: .bold))
                    .tracking(6)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(AppColors.primaryText)
                    .accessibilityLabel("代碼 \(viewModel.room.roomCode.map(String.init).joined(separator: " "))")
                Spacer()
                Button {
                    qrCodeRoom = viewModel.room
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: AppIcon.qrCode)
                            .font(.system(.title2, weight: .semibold))
                        Text("QR Code")
                            .font(.system(.caption, weight: .semibold))
                    }
                    .foregroundStyle(AppColors.accent)
                    .frame(minWidth: 56, minHeight: AccessibilityMetrics.minimumTapTarget)
                }
                .accessibilityLabel("顯示 QR Code 給家人掃")
                ShareLink(item: shareText(viewModel)) {
                    VStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(.title2, weight: .semibold))
                        Text("分享")
                            .font(.system(.caption, weight: .semibold))
                    }
                    .foregroundStyle(AppColors.accent)
                    .frame(minWidth: 56, minHeight: AccessibilityMetrics.minimumTapTarget)
                }
                .accessibilityLabel("分享房間代碼")
            }
        }
        .padding(AccessibilityMetrics.screenPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: AccessibilityMetrics.cornerRadius, style: .continuous))
    }

    private func shareText(_ viewModel: RoomViewModel) -> String {
        DeepLinkParser.shareMessage(roomName: viewModel.room.name, code: viewModel.room.roomCode, webGuestURL: dependencies.config.webGuestURL)
    }

    private func membersRow(_ viewModel: RoomViewModel) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(viewModel.members) { member in
                    RoomMemberAvatar(member: member, isMe: member.id == viewModel.me.id)
                }
            }
            .padding(.horizontal, 4)
        }
        .accessibilityLabel("房間裡有 \(viewModel.members.count) 個人")
    }

    private func sectionHeader(_ group: RoomViewModel.SectionGroup) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(group.title)
                .font(.app(.sectionTitle))
                .foregroundStyle(AppColors.primaryText)
            if let subtitle = group.subtitle?.nilIfBlank {
                Text(subtitle)
                    .font(.app(.body))
                    .foregroundStyle(AppColors.secondaryText)
            }
        }
        .padding(.top, 12)
        .padding(.horizontal, 4)
        .accessibilityAddTraits(.isHeader)
    }

    private func itemRow(_ item: MenuItem, _ viewModel: RoomViewModel) -> some View {
        let itemOptions = viewModel.options(for: item)
        let mine = viewModel.mySelections(for: item)
        return VStack(spacing: 8) {
            MenuItemCard(
                japaneseName: item.japaneseName,
                chineseName: item.chineseName,
                reading: viewModel.reading(for: item),
                price: item.price,
                note: item.description,
                optionsSummary: itemOptions.isEmpty ? nil : itemOptions.map { "\($0.displayName) \($0.priceDeltaText)" }.joined(separator: "、")
            ) {
                if itemOptions.isEmpty {
                    QuantityStepper(
                        quantity: viewModel.myQuantity(item: item),
                        onDecrement: { Task { await viewModel.adjust(item: item, by: -1) } },
                        onIncrement: { Task { await viewModel.adjust(item: item, by: 1) } }
                    )
                } else {
                    Button {
                        optionPickerItem = item
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus")
                            Text("選擇")
                        }
                        .font(.app(.buttonLabel))
                        .foregroundStyle(.white)
                        .frame(minWidth: 88, minHeight: AccessibilityMetrics.minimumTapTarget - 8)
                        .padding(.horizontal, 12)
                        .background(AppColors.accent, in: Capsule())
                    }
                    .buttonStyle(CardPressStyle())
                    .accessibilityLabel("選擇份量或套餐後加一份")
                }
            }

            // 有選項的菜：我點的每一種組合各自一列
            ForEach(mine.filter { !itemOptions.isEmpty || !$0.optionIds.isEmpty }) { selection in
                let names = viewModel.optionNames(for: selection)
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("我的：" + (names.isEmpty ? "不加選項" : names.map(\.displayName).joined(separator: "・")))
                            .font(.app(.body))
                            .foregroundStyle(AppColors.primaryText)
                        if let unit = viewModel.unitPrice(item: item, optionIds: selection.optionIds), let text = PriceFormatter.string(unit) {
                            Text("每份 \(text)")
                                .font(.app(.caption))
                                .foregroundStyle(AppColors.secondaryText)
                        }
                    }
                    Spacer()
                    QuantityStepper(
                        quantity: selection.quantity,
                        onDecrement: { Task { await viewModel.adjust(item: item, optionIds: selection.optionIds, by: -1) } },
                        onIncrement: { Task { await viewModel.adjust(item: item, optionIds: selection.optionIds, by: 1) } }
                    )
                }
                .padding(.horizontal, AccessibilityMetrics.screenPadding)
                .padding(.vertical, 10)
                .background(AppColors.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }
}

#Preview {
    let store = DiningSessionStore(defaults: UserDefaults(suiteName: "preview")!)
    NavigationStack { RoomView() }
        .environment(AppRouter())
        .environment(store)
        .environment(RoomSessionCoordinator.preview(sessionStore: store))
        .environment(\.dependencies, .preview)
}
