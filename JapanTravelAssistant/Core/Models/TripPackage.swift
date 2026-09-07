import CoreTransferable
import Foundation
import UniformTypeIdentifiers

extension UTType {
    /// 旅程檔（.jptrip），內容是 JSON。用 AirDrop、LINE 傳給家人，對方點開就匯入。
    static let jpTrip = UTType(exportedAs: "com.linzihao.japantravelassistant.trip", conformingTo: .json)
}

/// 一趟旅程的完整內容（旅程、地點、站點），可以匯出成檔案分享。
struct TripPackage: Codable, Hashable, Sendable, Identifiable {
    var id: UUID { trip.id }
    var version = TripPackage.currentVersion
    var trip: Trip
    var places: [Place]
    var stops: [ItineraryStop]

    /// 這個版本的 App 看得懂的旅程檔版本。收到更新的版本時請使用者先更新 App。
    static let currentVersion = 1
    static let fileExtension = "jptrip"

    var fileName: String {
        let safe = trip.name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        return "\(safe.isEmpty ? "旅程" : safe).\(Self.fileExtension)"
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    /// 打不開時丟的是白話錯誤（UserFacingError），畫面可以直接顯示。
    static func decode(_ data: Data) throws -> TripPackage {
        let decoder = JSONDecoder()
        if let header = try? decoder.decode(VersionHeader.self, from: data), let version = header.version, version > currentVersion {
            throw UserFacingError(
                title: "這個旅程檔是新版 App 做的",
                message: "請先到 App Store 更新「日本旅遊助手」，再打開這個檔案。",
                isRetryable: false
            )
        }
        do {
            return try decoder.decode(TripPackage.self, from: data)
        } catch {
            throw UserFacingError.unreadableTripFile
        }
    }

    private struct VersionHeader: Decodable {
        var version: Int?
    }

    /// 寫到暫存資料夾，給分享用
    func writeToTemporaryFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try encoded().write(to: url, options: .atomic)
        return url
    }
}

extension TripPackage: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .jpTrip) { package in
            SentTransferredFile(try package.writeToTemporaryFile())
        }
    }
}
