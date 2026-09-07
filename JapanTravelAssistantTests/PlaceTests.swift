import CoreLocation
import Foundation
import Testing
@testable import JapanTravelAssistant

@Suite("我要去一個地方")
struct PlaceTests {
    @Test("地點儲存：新增、更新、刪除")
    @MainActor
    func store() {
        let store = PlaceStore(directory: nil)
        let trip = store.addTrip(name: "測試")
        let hotel = Place(name: "飯店", address: "東京都", category: .hotel)
        let station = Place(name: "東京駅", latitude: 35.68, longitude: 139.76, category: .station)
        store.add(hotel, to: trip.id)
        store.add(station, to: trip.id)
        #expect(store.places(in: trip.id).map(\.name) == ["飯店", "東京駅"])

        var renamed = store.place(id: hotel.id)!
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

    @Test("搜尋結果是手機語言的寫法：日文名稱與地址要用日文反查的，查不到就留空")
    func searchResultUsesJapaneseDetails() async throws {
        let service = MockPlaceSearchService()
        let results = try await service.search("東京", near: nil)
        let hotel = results[1]
        #expect(hotel.name == "東京車站飯店")   // 繁中，不能拿來當日文名
        let japanese = await service.japaneseDetails(latitude: hotel.latitude, longitude: hotel.longitude)
        let place = hotel.toPlace(japanese: japanese)
        #expect(place.name == "東京車站飯店")
        #expect(place.japaneseName == "東京ステーションホテル")
        #expect(place.address == "〒100-0005 東京都千代田区丸の内1丁目9-1")
        #expect(place.staffName == "東京ステーションホテル")

        let fallback = hotel.toPlace(japanese: nil)
        #expect(fallback.japaneseName == nil)
        #expect(fallback.address == hotel.address)
        #expect(hotel.toPlace(japanese: JapanesePlaceDetails(name: " ", address: nil)).japaneseName == nil)
    }

    @Test("不認識的類型（新版 App 加的）退回「其他」，整份資料仍可讀")
    func unknownCategoryDecodesAsOther() throws {
        let json = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","name":"溫泉","category":"onsen"}"#
        let place = try JSONDecoder().decode(Place.self, from: Data(json.utf8))
        #expect(place.category == .other)
        #expect(place.name == "溫泉")
    }

    @Test("同名地點是不是同一個地方：地址都有但不同、或座標差很遠 → 不是")
    func looksLikeSamePlace() {
        let a = Place(name: "晚餐", address: "愛知県名古屋市中区栄3丁目")
        let b = Place(name: "晚餐", address: "愛知県名古屋市中村区名駅1丁目")
        let c = Place(name: "晚餐")
        #expect(!a.looksLikeSamePlace(as: b))
        #expect(a.looksLikeSamePlace(as: c) && c.looksLikeSamePlace(as: a))
        #expect(a.looksLikeSamePlace(as: Place(name: "晚餐", address: "愛知県名古屋市中区栄 3丁目")))   // 只差空白
        let near = Place(name: "x", latitude: 35.1681, longitude: 136.9086)
        #expect(near.looksLikeSamePlace(as: Place(name: "x", latitude: 35.1682, longitude: 136.9087)))
        #expect(!near.looksLikeSamePlace(as: Place(name: "x", latitude: 35.17, longitude: 136.88)))
    }
}

@Suite("導航連結")
struct NavigationURLTests {
    @Test("Google 地圖 App：沒座標時用地址，不會說「沒有地址」")
    func googleMapsUsesAddressWithoutCoordinate() throws {
        let place = Place(name: "名古屋城", address: "〒460-0031 愛知県名古屋市中区本丸1-1", japaneseName: "名古屋城")
        let url = try #require(LiveNavigationService.externalURL(for: place, provider: .googleMaps))
        #expect(url.scheme == "comgooglemaps")
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(items.first { $0.name == "daddr" }?.value == "名古屋城 〒460-0031 愛知県名古屋市中区本丸1-1")
        #expect(items.first { $0.name == "directionsmode" }?.value == "walking")

        let located = Place(name: "名古屋城", latitude: 35.1856, longitude: 136.8998)
        let locatedURL = try #require(LiveNavigationService.externalURL(for: located, provider: .googleMaps))
        let items2 = try #require(URLComponents(url: locatedURL, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(items2.first { $0.name == "daddr" }?.value == "35.1856,136.8998")

        #expect(LiveNavigationService.externalURL(for: Place(name: "什麼都沒有"), provider: .googleMaps) == nil)
        #expect(LiveNavigationService.googleWebURL(for: place) != nil)
        #expect(!Place(name: "什麼都沒有").canNavigate)
    }

    @Test("Yahoo! カーナビ：名稱含 & 或 + 也不會被截斷或變成空格")
    func yahooEncodesName() throws {
        let place = Place(name: "餐廳", latitude: 35.1681, longitude: 136.9086, japaneseName: "Bar & Grill A+B 名古屋")
        let url = try #require(LiveNavigationService.externalURL(for: place, provider: .yahooCarNavi))
        #expect(url.scheme == "yjcarnavi")
        #expect(url.absoluteString.contains("%26") && url.absoluteString.contains("%2B"))
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(items.first { $0.name == "name" }?.value == "Bar & Grill A+B 名古屋")
        #expect(items.first { $0.name == "lat" }?.value == "35.1681")
        #expect(items.first { $0.name == "lon" }?.value == "136.9086")
        #expect(LiveNavigationService.externalURL(for: Place(name: "沒座標", address: "東京都"), provider: .yahooCarNavi) == nil)
    }
}
