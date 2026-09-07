import AVFoundation
import Testing
@testable import JapanTravelAssistant

/// 畫面層裡可以抽出來單獨驗證的判斷邏輯。
@Suite("畫面可用性判斷")
struct ScreenAvailabilityTests {
    @Test("掃 QR Code：權限被拒 → 要給「前往設定」；被限制、沒相機、相機忙碌各自分開")
    func qrScanAvailability() {
        typealias A = QRScanAvailability
        #expect(A.resolve(status: .notDetermined, isSupported: true, isAvailable: true) == .checking)
        #expect(A.resolve(status: .denied, isSupported: true, isAvailable: false) == .permissionDenied)
        #expect(A.resolve(status: .denied, isSupported: true, isAvailable: false).canOpenSettings)
        #expect(A.resolve(status: .restricted, isSupported: true, isAvailable: false) == .permissionRestricted)
        #expect(!A.resolve(status: .restricted, isSupported: true, isAvailable: false).canOpenSettings)
        #expect(A.resolve(status: .authorized, isSupported: false, isAvailable: false) == .unsupported)
        #expect(A.resolve(status: .authorized, isSupported: true, isAvailable: false) == .cameraBusy)
        #expect(A.resolve(status: .authorized, isSupported: true, isAvailable: true) == .ready)
    }

    @Test("掃 QR Code 的說明文字：每種不能用的情況都有白話標題與下一步，且沒有技術詞")
    func qrScanCopy() {
        let cases: [QRScanAvailability] = [.permissionDenied, .permissionRestricted, .unsupported, .cameraBusy]
        for state in cases {
            #expect(!state.title.isEmpty && !state.message.isEmpty, "\(state)")
            #expect(!state.message.contains("API") && !state.message.contains("權限狀態"), "\(state)")
        }
        #expect(QRScanAvailability.permissionDenied.message.contains("設定"))
        #expect(QRScanAvailability.unsupported.message.contains("輸入代碼"))
    }

    @Test("給店員看的字級：一句話用最大字；地址那種多行內容上限 44pt；附照片時縮 0.8")
    func staffDisplayFontSize() {
        let sentence = "こちらの商品はありますか？"
        let address = "ここまでお願いします。\n東京ステーションホテル\n〒100-0005 東京都千代田区丸の内1丁目9-1"
        #expect(StaffDisplayView.heroFontSize(base: 52, hasImage: false, text: sentence) == 52)
        #expect(StaffDisplayView.heroFontSize(base: 52, hasImage: true, text: sentence) == 52 * 0.8)
        // 超大字體（AX 尺寸）時 base 會到 90 以上：地址壓在 44
        #expect(StaffDisplayView.heroFontSize(base: 92, hasImage: false, text: address) == 44)
        // 字體本來就比上限小就照原本的
        #expect(StaffDisplayView.heroFontSize(base: 40, hasImage: false, text: address) == 40)
        // 沒有換行但很長的一句也算長內容
        let long = String(repeating: "あ", count: 30)
        #expect(StaffDisplayView.heroFontSize(base: 60, hasImage: false, text: long) == 44)
    }
}
