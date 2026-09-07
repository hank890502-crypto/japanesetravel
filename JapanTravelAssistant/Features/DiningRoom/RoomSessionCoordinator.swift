import Foundation
import Observation

/// 一個房間 session 只有一個 RoomViewModel：點餐頁、本桌訂單、給店員看、QR Code 共用同一份，
/// 進出畫面、打開全螢幕 cover 都不會重建或停掉串流；只有真正離開房間（按離開、房間結束、session 被清）才 stop()。
///
/// 放在 Environment，跟著 DiningSessionStore.current 走：session 變了就換一份新的 ViewModel。
@Observable
@MainActor
final class RoomSessionCoordinator {
    /// 目前房間的 ViewModel；沒有在房間裡就是 nil。
    private(set) var viewModel: RoomViewModel?
    /// 房間結束（過期、房主關閉、這台手機已不是成員）時給長輩看的說明。按「回到餐廳」後清掉。
    private(set) var endedNotice: UserFacingError?

    @ObservationIgnored private let sessionStore: DiningSessionStore
    @ObservationIgnored private let roomRepository: any RoomRepository
    @ObservationIgnored private let menuRepository: any MenuRepository
    @ObservationIgnored private let orderRepository: any OrderRepository

    init(sessionStore: DiningSessionStore, roomRepository: any RoomRepository, menuRepository: any MenuRepository, orderRepository: any OrderRepository) {
        self.sessionStore = sessionStore
        self.roomRepository = roomRepository
        self.menuRepository = menuRepository
        self.orderRepository = orderRepository
        sync()
        observeSessionStore()
    }

    /// 建房／加入成功：存下 session 並立刻準備好 ViewModel（畫面 push 進去就有資料可用，不會閃「沒有房間」）。
    func enter(_ session: RoomSession) {
        sessionStore.current = session
        sync()
    }

    /// 真正離開房間：停掉串流、清掉 session。
    func leave() {
        viewModel?.stop()
        viewModel = nil
        endedNotice = nil
        sessionStore.leave()
    }

    /// 長輩看完「房間已經結束」的說明、按了回到餐廳。
    func dismissEndedNotice() {
        endedNotice = nil
    }

    /// 讓 viewModel 與 sessionStore.current 一致：房間換了就停掉舊的、建新的；沒有房間就停掉。
    func sync() {
        let session = sessionStore.current
        if let viewModel, viewModel.session == session { return }
        viewModel?.stop()
        viewModel = nil
        guard let session else { return }
        endedNotice = nil
        guard session.room.isJoinable else {
            endRoom(with: .roomEnded)
            return
        }
        let vm = RoomViewModel(session: session, roomRepository: roomRepository, menuRepository: menuRepository, orderRepository: orderRepository)
        vm.onSessionRestored = { [weak self] restored in
            // 先更新 store 再比對：sync() 看到 viewModel.session 已經等於新 session，不會重建
            self?.sessionStore.current = restored
        }
        vm.onRoomEnded = { [weak self] notice in
            self?.endRoom(with: notice)
        }
        viewModel = vm
        vm.start()
    }

    private func endRoom(with notice: UserFacingError) {
        viewModel?.stop()
        viewModel = nil
        endedNotice = notice
        sessionStore.leave()
    }

    /// DiningSessionStore.current 被別處改了（例如啟動時判定過期而清掉）→ 下一輪重新對齊。
    private func observeSessionStore() {
        withObservationTracking {
            _ = sessionStore.current
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.sync()
                self.observeSessionStore()
            }
        }
    }
}

extension RoomSessionCoordinator {
    /// #Preview 用：接 AppDependencies.preview 的 InMemory Repository。
    static func preview(sessionStore: DiningSessionStore) -> RoomSessionCoordinator {
        let deps = AppDependencies.preview
        return RoomSessionCoordinator(sessionStore: sessionStore, roomRepository: deps.roomRepository, menuRepository: deps.menuRepository, orderRepository: deps.orderRepository)
    }
}
