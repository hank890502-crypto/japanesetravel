import Foundation

/// 給 InMemory Repository 用的簡單「訂閱 → 廣播」工具。
/// 每個 key（通常是 roomId）可以有多個 AsyncStream 訂閱者。
struct ObserverRegistry<Value: Sendable> {
    private struct Entry {
        let key: UUID
        let continuation: AsyncStream<Value>.Continuation
    }

    private var entries: [UUID: Entry] = [:]

    /// 建立一個新的 stream。`onTerminate` 在訂閱者取消時被呼叫（用來把自己移除）。
    mutating func makeStream(key: UUID, onTerminate: @escaping @Sendable (UUID) -> Void) -> AsyncStream<Value> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<Value>.makeStream(bufferingPolicy: .bufferingNewest(1))
        continuation.onTermination = { _ in onTerminate(id) }
        entries[id] = Entry(key: key, continuation: continuation)
        return stream
    }

    mutating func remove(id: UUID) {
        entries[id] = nil
    }

    func broadcast(key: UUID, value: Value) {
        for entry in entries.values where entry.key == key {
            entry.continuation.yield(value)
        }
    }
}
