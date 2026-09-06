import CoreLocation
import Foundation
import Testing
@testable import JapanTravelAssistant

@Suite("我要去一個地方")
struct PlaceTests {
    @Test("地點儲存：新增在最前面、更新、刪除、最近用過移到最前")
    @MainActor
    func store() {
        let store = PlaceStore(directory: nil)
        let hotel = Place(name: "飯店", address: "東京都", category: .hotel)
        let station = Place(name: "東京駅", latitude: 35.68, longitude: 139.76, category: .station)
        store.add(hotel)
        store.add(station)
        #expect(store.places.map(\.name) == ["東京駅", "飯店"])

        store.markUsed(id: hotel.id)
        #expect(store.places.first?.id == hotel.id)

        var renamed = hotel
        renamed.name = "我們的飯店"
        store.update(renamed)
        #expect(store.place(id: hotel.id)?.name == "我們的飯店")

        store.remove(id: station.id)
        #expect(store.places.count == 1)
        #expect(hotel.canNavigate && station.canNavigate)
        #expect(!Place(name: "沒有地址").canNavigate)
    }

    @Test("舊版地點 JSON（沒有 category）仍可讀")
    func legacyDecode() throws {
        let json = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","name":"東京駅","address":"東京都千代田区"}"#
        let place = try JSONDecoder().decode(Place.self, from: Data(json.utf8))
        #expect(place.category == .other)
        #expect(place.address == "東京都千代田区")
    }

    @Test("搜尋結果轉成地點會帶座標與類型")
    func searchResultToPlace() async throws {
        let results = try await MockPlaceSearchService().search("東京", near: nil)
        #expect(results.count == 2)
        let place = results[1].toPlace()
        #expect(place.category == .hotel)
        #expect(place.hasCoordinate)
        #expect(place.phone == "+81-3-5220-1111")
    }
}
