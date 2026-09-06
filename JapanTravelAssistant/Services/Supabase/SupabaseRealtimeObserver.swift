import Foundation
import Supabase

/// 共用的「訂閱某房間的幾張表，一有變動就整份重抓」工具。
/// 策略刻意簡單：任何變動、任何重新連線，都重新抓一次完整資料，不做增量補洞。
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
                let channel = client.channel("room-\(roomId.uuidString.lowercased())-\(tables.joined(separator: "-"))")
                let filter = "room_id=eq.\(roomId.uuidString.lowercased())"
                let changeStreams = tables.map { table in
                    channel.postgresChange(AnyAction.self, schema: "public", table: table, filter: filter)
                }

                // 先給目前狀態
                if let value = try? await fetch() { continuation.yield(value) }

                await channel.subscribe()

                // 訂閱成功（含重連）→ 整份重抓
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
                }
                statusTask.cancel()
                await client.removeChannel(channel)
                continuation.finish()
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
