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
    var version = 1
    var trip: Trip
    var places: [Place]
    var stops: [ItineraryStop]

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

    static func decode(_ data: Data) throws -> TripPackage {
        try JSONDecoder().decode(TripPackage.self, from: data)
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
