import Foundation
import Supabase

/// 共用的「訂閱某房間的幾張表，一有變動就整份重抓」工具。
/// 策略刻意簡單：任何變動、任何重新連線，都重新抓一次完整資料，不做增量補洞。
///
/// 串流「結束」代表出了問題（抓不到資料、訂閱失敗、連線斷了）：上層（RoomViewModel）會顯示「無法同步」並在幾秒後重新呼叫，
/// 所以這裡任何失敗都一定要 `finish()`，不能默默等下去。
enum SupabaseRealtimeObserver {
    /// - Parameters:
    ///   - tables: 要監聽的資料表（都必須有 room_id 欄位）
    ///   - fetch: 重抓完整資料的方法
    static func stream<Value: Sendable>(
        client: SupabaseClient,
        roomId: UUID,
        tables: [String],
        fetch: @escaping @Sendable () async throws -> Value
    ) -> AsyncStream<Value> {
        AsyncStream { continuation in
            let task = Task {
                // 每一條串流都用獨一無二的 channel 名稱：removeChannel 是以名稱為 key，
                // 同名會把別的畫面正在用的訂閱一起拆掉（之前「本桌訂單」回來就不再更新的原因）。
                let roomKey = roomId.uuidString.lowercased()
                let topic = "room-\(roomKey)-\(tables.joined(separator: "-"))-\(UUID().uuidString.lowercased())"
                let channel = client.channel(topic)
                let changeStreams = tables.map { table in
                    channel.postgresChange(AnyAction.self, schema: "public", table: table, filter: .eq("room_id", value: roomKey))
                }

                func finish() async {
                    await client.removeChannel(channel)
                    continuation.finish()
                }

                // 先給目前狀態；抓不到（沒網路、身分失效）就結束，讓上層顯示「無法同步」並稍後重試
                do {
                    continuation.yield(try await fetch())
                } catch {
                    await finish()
                    return
                }
                if Task.isCancelled { await finish(); return }

                // 訂閱失敗（含重試多次後放棄）同樣結束串流，不要卡在「正在載入」
                do {
                    try await channel.subscribeWithError()
                } catch {
                    await finish()
                    return
                }

                // 訂閱成功（含重連）→ 整份重抓，補上訂閱前的空窗
                let statusTask = Task {
                    for await status in channel.statusChange where status == .subscribed {
                        if let value = try? await fetch() { continuation.yield(value) }
                    }
                }

                // 任何一張表有變動 → 整份重抓。連續的變動（例如一次上傳 30 道菜）合併成一次。
                let coalescer = RefetchCoalescer {
                    if let value = try? await fetch() { continuation.yield(value) }
                }
                await withTaskGroup(of: Void.self) { group in
                    for changes in changeStreams {
                        group.addTask {
                            for await _ in changes {
                                await coalescer.trigger()
                            }
                        }
                    }
                    // 連上之後若整條 WebSocket 斷掉，就結束串流讓上層重建（並提示「無法同步」）。
                    // statusChange 一開始會先回放目前狀態，所以要等看過 .connected 之後的 .disconnected 才算斷線。
                    group.addTask {
                        var wasConnected = false
                        for await status in client.realtimeV2.statusChange {
                            if Task.isCancelled { return }
                            switch status {
                            case .connected: wasConnected = true
                            case .disconnected where wasConnected: return
                            default: break
                            }
                        }
                    }
                    // 任何一個子任務結束（斷線、串流被取消）→ 整組收掉
                    await group.next()
                    group.cancelAll()
                }
                statusTask.cancel()
                await finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// 短時間內多次觸發只執行一次（等 200ms 沒有新的觸發再跑）。
private actor RefetchCoalescer {
    private let action: @Sendable () async -> Void
    private var pending: Task<Void, Never>?

    init(action: @escaping @Sendable () async -> Void) {
        self.action = action
    }

    func trigger() {
        pending?.cancel()
        pending = Task { [action] in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            await action()
        }
    }
}
