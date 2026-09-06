# 日本旅遊助手（JapanTravelAssistant）

給不會日文的台灣家庭、特別是長輩使用的日本自由行 iOS App。

- 說話：飯店、租車、餐廳、溫泉、購物、交通、緊急常用日文，一鍵給店員看、播放。
- 看懂：拍菜單（支援直排）、ChatGPT 匯入、分類、選項、羅馬拼音、離線翻譯。
- 一起點餐：房主建房、家人掃 QR 或輸入代碼加入，每人各自點，房主即時彙總。沒裝 App 的家人可用網頁版（`web/guest/`）。

## 開發

- Xcode 26、iOS 17+、SwiftUI。用 XcodeGen 產生專案：`xcodegen generate`（已附 `.xcodeproj`，可直接開）。
- 多人點餐需要 Supabase：見 `docs/SUPABASE_SETUP.md`。設定放在 `Config/Secrets.xcconfig`（不進 Git，範本是 `Secrets.example.xcconfig`）。
- 架構說明：`docs/ARCHITECTURE.md`。
