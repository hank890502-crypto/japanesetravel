# 日本自由行旅遊助手 — 架構文件（v0.1，M0 前）

> 產品原則：使用者只需要知道「我現在想做什麼」，技術複雜度全部藏在 App 後面。
> 核心使用者：65～75 歲、不會日文、手機操作能力普通或偏弱。

---

## 1. 整體架構

採用 **Feature-based + 分層架構**，由上到下：

```
SwiftUI View（只負責顯示、把使用者動作交給 ViewModel）
        │
ViewModel（@Observable、@MainActor；持有 UI State、呼叫 Repository / Service）
        │
Repository（RoomRepository / MenuRepository / OrderRepository：領域操作，回傳 Domain Model）
        │
Service（SupabaseService / OCRService / AIService / SpeechService / NavigationService）
        │
外部能力（Supabase、Vision、AVSpeech、MapKit、未來 AI Backend）
```

規則：

1. View 永遠不直接碰 Supabase、Vision、AVSpeech。
2. Repository / Service 全部是 **protocol**，每個至少有一個 `Live` 實作與一個 `InMemory`/`Mock` 實作（給 Preview 與測試）。
3. Domain Model 放在 `Core/Models`，是 `Codable + Identifiable + Hashable + Sendable` 的純資料 struct。
4. 錯誤一律轉成 `UserFacingError`（白話中文），View 只顯示 `UserFacingError.message`。
5. 沒有 Supabase 設定、沒有網路、沒有 AI Key 時，App 都要能啟動，只是對應功能顯示白話提示。

### 1.1 Swift 語言設定

- iOS 17.0 deployment target。
- Swift language mode 先用 **Swift 5 + Strict Concurrency = Complete**（警告不擋 build），避免第三方 SDK 在 Swift 6 mode 下產生大量阻擋錯誤。日後穩定再切 Swift 6。
- 全面使用 `async/await`；ViewModel 標記 `@MainActor`。

### 1.2 外部相依

| 階段 | 套件 | 用途 |
|---|---|---|
| M0–M2 | 無 | 全部用 Apple 原生框架（Vision、VisionKit、PhotosUI、AVFoundation、MapKit、CoreImage） |
| M3 | `supabase-swift`（SPM） | Database / Auth(Anonymous) / Realtime / Storage |

QR Code 產生用 CoreImage `CIFilter.qrCodeGenerator`，掃描用 `DataScannerViewController`，都不需要第三方套件。

---

## 2. 資料夾結構（Xcode 專案）

```
日本旅遊 App/
├── project.yml                     ← XcodeGen 設定，可重新產生 .xcodeproj
├── .gitignore
├── Config/
│   ├── Shared.xcconfig             ← 共用設定（deployment target 等）
│   ├── Secrets.example.xcconfig    ← 範本（commit）
│   └── Secrets.xcconfig            ← 真實值（gitignore）
├── docs/
│   └── ARCHITECTURE.md
├── supabase/
│   └── migrations/0001_initial.sql
└── JapanTravelAssistant/
    ├── App/
    │   ├── JapanTravelAssistantApp.swift   ← @main，建立 AppDependencies
    │   ├── AppDependencies.swift           ← DI 容器（live / preview）
    │   ├── AppRouter.swift                 ← Route enum + NavigationPath
    │   └── RootView.swift                  ← NavigationStack 根
    ├── Core/
    │   ├── Models/          Trip, DiningRoom, RoomMember, Menu, MenuSection, MenuItem,
    │   │                    MenuSelection, ScanRecord, Phrase, Place, OrderSummary
    │   ├── Networking/      （M3：Supabase 設定、Realtime 事件型別）
    │   ├── Persistence/     （本機草稿：MenuDraftStore，之後可換 SwiftData）
    │   ├── Utilities/       AppConfig, UserFacingError, RoomCodeGenerator, PriceParser
    │   └── Extensions/
    ├── Features/
    │   ├── Home/            HomeView, HomeViewModel
    │   ├── Communication/   類別列表 → 句子列表 → 給店員看
    │   ├── CameraScanner/   拍照 / 相簿選圖 / OCR 結果編輯
    │   ├── Menu/            建立與編輯結構化菜單
    │   ├── DiningRoom/      建房、加入、點餐、Host 彙總
    │   ├── Shopping/        相簿找商品
    │   ├── Navigation/      地點列表、開啟地圖
    │   ├── Emergency/       緊急句子
    │   └── Settings/        導航 App 偏好、AI 狀態
    ├── Services/
    │   ├── OCR/             OCRService(protocol), VisionOCRService, MockOCRService
    │   ├── AI/              AIService(protocol), DisabledAIService, MockAIService
    │   ├── Supabase/        SupabaseService(protocol), LiveSupabaseService, DTO mapping
    │   ├── Speech/          SpeechService(protocol), AVSpeechService
    │   └── Maps/            NavigationService(protocol), AppleMapsProvider, GoogleMapsProvider…
    ├── Repositories/
    │   ├── RoomRepository/  protocol + InMemoryRoomRepository + SupabaseRoomRepository
    │   ├── MenuRepository/
    │   └── OrderRepository/
    ├── DesignSystem/
    │   ├── Typography/      AppTypography（Dynamic Type 對應）
    │   ├── Components/      LargeActionCard, PrimaryButton, SecondaryButton, ErrorBanner,
    │   │                    StaffDisplayView, JapanesePhraseCard, MenuItemCard,
    │   │                    QuantityStepper, RoomMemberAvatar, ElderlyNavigationBar
    │   ├── Icons/           AppIcon enum（SF Symbol 名稱集中管理）
    │   └── Accessibility/   最小點擊區、VoiceOver helper
    └── Resources/
        ├── Assets.xcassets
        ├── Localizations/   zh-Hant 為主
        └── Phrases/         phrases.json（溝通助手內容，資料與程式分離）
```

---

## 3. Domain Model（Swift）

所有 model 皆為 `struct: Codable, Identifiable, Hashable, Sendable`，
JSON key 以 snake_case 對應資料庫欄位（decoder 設定 `.convertFromSnakeCase`）。

```swift
struct Trip          { id: UUID; name: String; startDate: Date?; endDate: Date? }

struct DiningRoom    { id: UUID; tripId: UUID?; name: String; roomCode: String
                       hostUserId: UUID; status: RoomStatus; createdAt: Date; expiresAt: Date }

struct RoomMember    { id: UUID; roomId: UUID; userId: UUID; displayName: String
                       isHost: Bool; createdAt: Date }

struct Menu          { id: UUID; roomId: UUID?; restaurantName: String?; createdAt: Date }
                       // roomId 為 nil = 本機草稿（還沒建房）

struct MenuSection   { id: UUID; menuId: UUID; nameJapanese: String; nameChinese: String?; sortOrder: Int }

struct MenuItem      { id: UUID; menuId: UUID; sectionId: UUID?
                       japaneseName: String; chineseName: String?; reading: String?
                       description: String?; price: Decimal?; currency: String   // "JPY"
                       isRecommended: Bool; sortOrder: Int
                       sourceConfidence: Double?; sourceImagePath: String? }

struct MenuSelection { id: UUID; roomId: UUID; memberId: UUID; menuItemId: UUID
                       quantity: Int; note: String?; updatedAt: Date }

struct ScanRecord    { id: UUID; roomId: UUID?; menuId: UUID?; storagePath: String?
                       ocrText: String?; createdAt: Date }

// 純 App 端（不進資料庫）
struct Phrase        { id: String; category: PhraseCategory; chinese: String; japanese: String; reading: String? }
struct Place         { id: UUID; name: String; address: String?; latitude: Double?; longitude: Double? }
struct OrderSummaryLine { menuItem: MenuItem; totalQuantity: Int; byMember: [(RoomMember, Int)] }
```

**與你原始設計的差異（刻意的）：**

| 你的設計 | 這裡 | 原因 |
|---|---|---|
| `DiningRoom.hostMemberId` | `hostUserId` | 建房時 room 與 member 同一筆交易建立，用 user id 避免循環相依；`hostMember` 可從 members 內 `isHost` 取得 |
| `Menu.roomId` 必填 | Swift 端 optional | 使用者先拍菜單、再建房。草稿階段沒有 room；上傳時才綁定 |
| — | `DiningRoom.expiresAt`、`status` | 「離開後資料仍合理存在」但不永久：預設 48 小時後過期，可清理 |
| — | `RoomMember.userId` | 對應 Supabase 匿名使用者，RLS 需要 |

點餐數量的原則不變：**每位成員 × 每個品項一列**，`unique(room_id, member_id, menu_item_id)`，用 upsert，不會有多人搶寫同一個數字的問題。

---

## 4. Supabase Schema

完整 SQL 在 `supabase/migrations/0001_initial.sql`，重點設計：

### 4.1 身分
- 使用 **Supabase Anonymous Sign-in**（Dashboard 打開即可）。每台裝置第一次啟動自動取得一個匿名 `auth.users` 列，session 由 SDK 存在 Keychain。
- 不要 Email / Password / 手機 / Sign in with Apple。
- 未來 Web Guest 用同一機制（supabase-js 也支援匿名登入），schema 不需改。

### 4.2 資料表
`trips`, `dining_rooms`, `room_members`, `menus`, `menu_sections`, `menu_items`, `menu_selections`, `scan_records`

### 4.3 RLS（Row Level Security）
- 全部資料表開啟 RLS。
- 核心 helper：`is_room_member(room_id)` → 目前使用者是否為該房成員。
- 成員可讀房間內所有資料；只能寫自己的 `menu_selections`（`member.user_id = auth.uid()`）。
- 菜單編輯（menus / menu_sections / menu_items）：房主可寫；M3 起也允許成員修改 `chinese_name`（家人幫忙翻譯）。

### 4.4 RPC（透過 `SECURITY DEFINER` 函式繞過「還不是成員所以查不到房間」的雞生蛋問題）
- `create_room(p_name, p_display_name)` → 產生唯一 room code、建立房間 + 房主成員，一筆交易。
- `join_room(p_code, p_display_name)` → 依代碼找到未過期的開放房間，建立/更新成員，回傳房間與成員。
- `room_order_summary` view → 每個品項的總數（`security_invoker`，仍受 RLS 限制）。

### 4.5 Realtime
- 將 `menu_selections`, `room_members`, `menu_items`, `menu_sections`, `menus` 加入 `supabase_realtime` publication。
- Client 訂閱 `postgres_changes`，filter `room_id=eq.<roomId>`。
- 斷線重連策略：重連成功後 **整份重新拉取**（selections 是 upsert 語意，重拉不會出錯），不做增量補洞。

### 4.6 Room code
6 碼、字元集 `ABCDEFGHJKLMNPQRSTUVWXYZ23456789`（去掉 0/O/1/I 避免長輩看錯），大寫，衝突則重試。

---

## 5. Navigation 結構

**不用 TabView**（長輩容易誤觸、且四大入口已經是首頁）。單一 `NavigationStack` + typed `Route`：

```
Home（4 大卡片）
├─ 🗣 我要跟人說話 ─→ CommunicationCategories ─→ PhraseList(category) ─→ [fullScreenCover] StaffDisplay
├─ 📷 我要看懂這個 ─→ UnderstandHub
│      ├─ 🍽 看菜單、一起點餐 ─→ RestaurantHub
│      │       ├─ 拍菜單建立點餐 ─→ MenuScan ─→ OCRReview ─→ MenuEdit ─→ CreateRoom ─→ RoomHost
│      │       └─ 加入家人的點餐 ─→ JoinRoom(code) ─→ RoomMember
│      └─ 🛍 找商品 ─→ ShoppingPhotoPick ─→ ProductQuestions ─→ [fullScreenCover] StaffDisplay
├─ 🧭 我要去一個地方 ─→ PlaceList ─→ PlaceDetail ─→ 開啟外部地圖 App
└─ 🆘 我遇到問題 ─→ EmergencyList ─→ [fullScreenCover] StaffDisplay
```

- `AppRouter`（`@Observable`）持有 `NavigationPath`；Deep link `jptravel://join?code=A8F3K2` 直接 push `JoinRoom`。
- 「給店員看」與相機是 `fullScreenCover`，關閉鍵大且固定在同一位置。
- 每頁上方統一 `ElderlyNavigationBar`：大字返回「‹ 上一頁」+ 頁面標題。

### Deep link / QR（免費簽章的限制）
Universal Links 需要 Associated Domains entitlement，**免費簽章無法使用**。因此：
- 第一階段 QR 內容 = `jptravel://join?code=A8F3K2`，並且畫面上永遠同時顯示大字代碼（長輩可以直接念給家人打字）。
- 未來有 Web 與付費帳號時，QR 改為 `https://<domain>/room/A8F3K2`，App 端只需在 `DeepLinkParser` 多接一種格式。

---

## 6. Dependency Injection

不用 singleton，用一個明確的容器 + SwiftUI Environment：

```swift
struct AppDependencies {
    let config: AppConfig
    let ocr: any OCRService
    let ai: any AIService
    let speech: any SpeechService
    let navigation: any NavigationService
    let roomRepository: any RoomRepository
    let menuRepository: any MenuRepository
    let orderRepository: any OrderRepository

    static func live(config: AppConfig) -> AppDependencies   // 真實實作；沒有 Supabase 設定時自動退回 InMemory
    static var preview: AppDependencies                      // 全部 Mock / InMemory，給 #Preview 與測試
}

extension EnvironmentValues { @Entry var dependencies: AppDependencies = .preview }
```

- `@main` 讀 `AppConfig`（來自 xcconfig → Info.plist），建立 `.live`，用 `.environment(\.dependencies, deps)` 注入。
- View 取 `@Environment(\.dependencies)`，在 `init`/`task` 建立 ViewModel 並把需要的 protocol 傳進去。
- ViewModel 只依賴 protocol，因此每個 View 的 `#Preview` 都用 `.preview` 就能跑。

### Secrets
- `Config/Secrets.xcconfig`（gitignore）：`SUPABASE_URL`, `SUPABASE_ANON_KEY`。
- `Info.plist` 以 `$(SUPABASE_URL)` 引用；`AppConfig` 讀取，缺值 → `isCollaborationAvailable = false`，UI 顯示「多人點餐功能尚未設定」。
- Supabase anon key 是公開 key（安全性靠 RLS），但仍不進 Git。
- 任何 AI Key **永遠不進 App**；未來 `RemoteAIService` 打自己的 backend。

---

## 7. 里程碑與 M0 實作計畫

| 里程碑 | 內容 | 外部設定 |
|---|---|---|
| M0 App Shell | 專案、DI、Router、Design System、首頁 + 4 個佔位頁、protocol 全部就位 | 無 |
| M1 Communication | phrases.json、類別/句子列表、給店員看、AVSpeech 播放、相簿找商品 | 無 |
| M2 Menu Scanner | 相機 / PhotosPicker、Vision OCR(ja)、OCR 結果編輯、價格解析、建立 Menu/MenuItem 草稿 | 無 |
| M3 Collaborative Dining | supabase-swift、匿名登入、建房/加入、Realtime、每人數量、Host 彙總 | Supabase 專案 + 跑 SQL + 開 Anonymous |
| M4 Room Sharing | QR 產生/掃描、`jptravel://` deep link、Web Guest 說明文件 | 無 |
| M5 AI Adapter | Provider 設定 UI、Mock 翻譯流程、Remote backend interface | 無 |

### M0 檔案清單（預計）
- `project.yml`, `.gitignore`, `Config/*.xcconfig`
- `App/`：App, AppDependencies, AppRouter, RootView
- `Core/Models/`：全部 domain model
- `Core/Utilities/`：AppConfig, UserFacingError, RoomCodeGenerator
- `Services/*/`：全部 protocol + Disabled/Mock 實作（Live 實作在對應里程碑補）
- `Repositories/*/`：protocol + InMemory 實作
- `DesignSystem/`：AppTypography, LargeActionCard, PrimaryButton, SecondaryButton, ErrorBanner, ElderlyNavigationBar, StaffDisplayView
- `Features/Home/HomeView`；其他 Feature 各一個佔位頁（有標題、有返回）

### M0 完成標準
1. 用 Xcode 開啟、免費簽章安裝到 iPhone，能啟動。
2. 首頁 4 張大卡片，每張可進入對應頁面並返回。
3. 設定「文字大小」到最大（輔助使用 → 更大文字）仍不破版。
4. VoiceOver 能唸出每張卡片的中文標籤。
5. 每個 View 都有可執行的 `#Preview`。

---

## 附錄 A：開發用啟動參數（只在 DEBUG 生效）

在 Xcode 的 Scheme → Run → Arguments，或用 `xcrun simctl launch`，加上 `-openRoute <名稱>` 可以直接打開某個畫面，方便截圖與測試：

`communication`、`phrases:shopping`（任一分類 rawValue）、`emergency`、`understand`、`restaurant`、`menuScan`、`menuReview`、`chatGPTImport`、`createRoom`、`room`、`orderSummary`、`joinRoom`、`findProduct`、`places`、`tripPlaces`、`placeDetail`、`tripImport`、`tripMap`、`staffAddress`（地址給司機看）、`settings`、`assistant`

另外幾個截圖用的開關（可與 `-openRoute` 併用）：`-simulateAppleIntelligenceUnavailable`（模擬不支援 Apple 智慧）、`-openQRScanner`（加入房間頁直接開掃碼）、`-editFirstItem`（檢查菜單頁直接開第一道菜）、`-showSectionPicker`（編輯頁直接開分類選單）、`-focusPrice`（編輯頁直接把游標放在價格欄）。

實作在 `Core/Utilities/DebugLaunchOptions.swift`，Release 版本完全忽略。

## 附錄 B：菜單 OCR 除錯流程

1. 把 iPhone 拍的菜單照片（JPG/PNG/HEIC 皆可）放進 `samples/`。
2. 在專案根目錄執行：`tools/ocr-debug.sh samples/照片檔名.jpg`
3. 會印出 Vision 讀到的每一塊文字（含座標與信心值）、版面分析後的「菜 + 價格」與「其他文字」。
   App 內用的是同一份 `PriceParser` 與 `MenuLayoutAnalyzer`，所以在 Mac 上調好就等於 App 內調好。

辨識引擎（`LiveMenuRecognitionService`）：
1. **Live Text（VisionKit ImageAnalyzer）為主**：支援直排日文，輸出是閱讀順序的整行文字（無座標）。
   → `MenuTranscriptParser`：價格行配給前面最近的品名行；括號行、「の」結尾、≤3 字的上一行併入品名；
   英文／韓文／簡中翻譯行略過；分類標題與 ※ 說明進「其他文字」。
2. **Vision 為備援**（Live Text 完全沒讀到時）：`MenuLayoutAnalyzer` 以價格為錨點、用座標配對。

價格（`PriceParser` + `KanjiNumberParser`）：¥540、540円、·540（Live Text 把 ¥ 讀成 ·）、各520円、
八四〇円／一一五〇円／千二百円（漢數字）、（税込418円）優先取税込價。

中文（檢查頁自動執行）：先用內建詞彙表 `Resources/Glossary/menu-glossary.json`（離線、即時），
剩下的交給 Apple 內建離線翻譯（iOS 18+，`Translation` framework，第一次會請使用者下載語言包）。

## 附錄 C：用 ChatGPT 翻譯菜單（不接 API 的高品質翻譯路徑）

流程：`ChatGPTImportView`（拍菜單頁與檢查頁都有入口）
1. 複製提示文字（`ChatGPTMenuPrompt.text`），可直接打開 ChatGPT App。
2. 使用者在 ChatGPT 貼上提示 + 菜單照片。
3. 把回覆貼回 App → `MenuImportParser` 解析（容忍 markdown 表格、程式碼區塊、編號、JSON）
   → `MenuDraftStore.merge(imported:)`：日文名對得上的更新中文／價格／說明／分類，對不上的新增。

輸出格式（一行一道菜）：`日文原名 | 繁體中文 | 價格 | 說明`，分類為 `## 日文分類 | 中文分類`（必填），前後有「菜單開始／菜單結束」。

### 分類
- `MenuItemDraft.sectionName`（日文）+ `MenuDraft.sectionChineseNames`（日文 → 中文）；`groupedItems` 依第一次出現順序分組，沒有分類的放最後。
- 來源：Live Text 讀到已知分類標題（`MenuTranscriptParser.sectionHeaders`）套用到後面的菜；連續兩個標題中間沒有菜（多欄）視為無法判斷、不套用。
  ChatGPT 匯入直接帶分類與中文；編輯畫面可選現有分類或新增。
- 分類中文缺的時候，與菜名一樣走詞彙表 → Apple 離線翻譯。
- `toBundle()` 建立 `MenuSection`（含 nameChinese）並把 item 綁到 sectionId。

### 選項（份量、套餐升級、配料）
- `MenuItemOption`：`groupName`（中文群組）、`nameJapanese`、`nameChinese`、`priceDelta`（相對基本價，可負）。同群組單選。
- `MenuSelection.optionIds` + `variantKey`（排序後的 option id）：同一道菜不同組合各自計數。
  DB：`menu_item_options` 表、`menu_selections.option_ids / variant_key`，unique 改為 (room, member, item, variant_key)。
- `OrderSummaryBuilder` 依 (item, variant) 產生行，`unitPrice = price + Σdelta`，`staffDisplayName` = 菜名（選項日文）。
- ChatGPT 格式：菜的下一行 `選項 | 群組 | 日文 | 中文 | 價差`；編輯畫面可手動增刪。

### 羅馬拼音
- `JapaneseReading`：用 `CFStringTokenizer` 的 Latin transcription 離線產生（漢字→romaji→平假名）。
- `MenuItemDraft.reading`：ChatGPT 第 5 欄優先，否則進檢查頁時 `fillMissingReadings()` 自動補；改日文名時重算。
- 顯示在菜名下方（斜體），M3 的點餐與彙總畫面沿用。

## 附錄 D：M3 多人點餐的實作重點

- `AppDependencies.live`：有 `SUPABASE_URL` / `SUPABASE_ANON_KEY` 就用 `LiveSupabaseService` + 三個 Supabase Repository；沒有就用 InMemory（整個流程仍可在單機上跑）。
- `SupabaseCoding`：snake_case ↔ camelCase、Postgres 時間格式。Domain Model 直接解碼；寫入用各 Repository 內的 Row 結構（含反正規化的 `room_id`）。
- `SupabaseRealtimeObserver`：每條串流一個 channel（名稱帶隨機 UUID，removeChannel 只會影響自己），監聽幾張表的 postgres_changes（filter `room_id=eq.`），任何變動或重新訂閱都整份重抓。
  初次抓取失敗、`subscribeWithError()` 失敗、連上後 WebSocket 斷線 → 一律 `finish()` 串流，讓上層顯示「無法同步」並重試。
- `RoomViewModel`：先 `restoreSession`（確認這台手機還是成員；身分變了家人會重新加入、房主會被告知要重建；房間結束會直接告知），
  再開三條串流（成員、菜單、選擇）；串流結束 = 斷線 → 顯示「無法同步」並 3 秒後重新訂閱。
  + / − 用樂觀更新：每個 (菜, 選項組合) 只保留一個目標值，用序列化的寫入送最新目標（連按合併），重抓時在途的 key 以本機目標為準，失敗只還原那一個 key。
  名單裡沒有自己、房間過期 → `roomEnded`，通知持有者。
- `RoomSessionCoordinator`（Environment）：**一個房間 session 只有一個 RoomViewModel**，點餐頁／本桌訂單／給店員看／QR Code 共用；
  跟著 `DiningSessionStore.current` 走，只有真正離開（按離開、房間結束、session 被清）才 `stop()`。畫面不在 onAppear/onDisappear 建立或清掉 VM
  （fullScreenCover 會讓底層收到 onDisappear）；cover 內容讀快照。
- `DiningSessionStore`：目前房間存在 UserDefaults，重開 App 可從餐廳頁「回到房間」；沒有 Supabase 設定（InMemory）時啟動就清掉，不還原不存在的房間。
- 畫面：`CreateRoomView`（建房 + 上傳菜單）、`JoinRoomView`（代碼）、`RoomView`（菜單 + 每人自己的數量 + 成員 + 分享）、`OptionPickerSheet`、`OrderSummaryView`（彙總 + 金額 + 給店員看 `StaffOrderView`）。
- 設定步驟見 `docs/SUPABASE_SETUP.md`。
- 房間代碼一律由資料庫 `create_room(p_name, p_display_name)` 產生，沒有「指定代碼」（之前的測試後門讓任何人能關掉別人的房間，已在 `0002_hardening.sql` 移除）。
  `SupabaseErrorMapper.map(_:context:)` 依 Postgres 錯誤代碼與呼叫情境（建房／加入／點餐／上傳菜單…）給不同的白話訊息。
- 資料庫強化（`0002_hardening.sql`）：建房節流（同時 5 間、每小時 20 次）、點餐只能寫進開著且未過期的房間、`variant_key` 由 trigger 統一產生
  （小寫 UUID 排序後以「,」連接，App 與網頁版同規則）、家人只能改翻譯欄位、成員不能改 is_host、`cleanup_expired_rooms()` + pg_cron。
- QR：`RoomQRCodeSheet`（CoreImage 產生 `jptravel://join?code=`）、`QRCodeScannerView`（VisionKit DataScanner，只在真機可用）。

## 附錄 E：效能與 iPad

- iPad 正式支援（TARGETED_DEVICE_FAMILY 1,2），iPad 四個方向可轉；內容用 `readableWidth()` 限制在 720pt 置中。
- `RoomViewModel` 把分組、彙總、每道菜的選項、我的數量、拼音都在資料變動時算一次存起來（`rebuildMenuCaches` / `rebuildOrderCaches`），畫面重繪只查表。
- `MenuDraftStore.persist()` 在背景寫檔，300ms 內連續變動只寫一次。
- `SupabaseRealtimeObserver` 用 `RefetchCoalescer` 把 200ms 內的連續變動合併成一次重抓。
- 拼音兩層保險：建房前 `fillMissingReadings()`；房間畫面缺拼音時本機產生並快取（家人加入也看得到）。

## 附錄 F：M4 房間分享與 Web Guest

- `web/guest/`：純靜態網頁（index.html + app.js + config.js），用 supabase-js 直接連同一個 Supabase：匿名登入 → `join_room` → 讀 6 張表 → realtime 訂閱 → upsert `menu_selections`。
  所有來自資料庫的字串經 `esc()` 或 DOM API 才進畫面；重開頁面時先用 `join_room` 向伺服器確認成員仍在才還原；房間過期／結束會停用 + −。
  功能與 App 對齊：分類列、每人自己的數量、選項（同群組單選）、本桌訂單與總金額、「打開 App」按鈕（`jptravel://join?code=`）。
  網址參數：`?code=XXXX`（必要）、`&name=媽媽`（選填，直接加入）。部署與本機試跑見 `web/README.md`。
- App 設定 `WEB_GUEST_URL`（選填）：有值時 `DeepLinkParser.shareURL` 回傳 `https://…/?code=XXXX`，QR Code 與分享都用它；
  沒有值時維持 `jptravel://join?code=`。`DeepLinkParser.parse` 同時接受 `jptravel://`、`https://…?code=`、`https://…/room/CODE`。
- 之後有付費開發者帳號：加 Associated Domains + AASA，https 連結會直接開 App（程式不用改）。

## 附錄 G：M5 AI Adapter

- `AIService` protocol 不變；實作有 `DisabledAIService`（預設）、`MockAIService`（假資料）、`RemoteAIService`（自己的伺服器，HTTP JSON，規格見 `docs/AI_BACKEND.md`）。
- `AIServiceRouter` 依 `SettingsStore` 的選擇即時轉發；`remoteBackend` 沒有有效網址時等同未啟用。App 內永遠沒有 AI 金鑰。
- 設定頁（首頁右上「設定」）：AI 幫手、預設地圖 App、多人點餐與網頁版狀態。
- 接入點：檢查菜單「AI 幫我整理菜單」（結果走 `MenuDraftStore.merge`）、找商品「AI 幫我認這個商品」。未啟用時這兩顆按鈕直接不顯示（長輩在設定頁沒有能自己完成的動作；設定由家人代勞）。
- 伺服器範本：`supabase/functions/ai/index.ts`（Supabase Edge Function，預設 OpenAI，金鑰用 `supabase secrets set`）。
  共享密鑰：伺服器環境變數 `APP_TOKEN` ↔ App 設定頁「伺服器密碼」（`RemoteAIService.appToken`，header `X-App-Token`），不符回 401。

## 附錄 H：M6 我要去一個地方

- `Place` 加上 `category`（飯店／車站／餐廳／商店／景點／其他）、`phone`、`note`；`PlaceStore` 存 Documents/places.json，最近使用的排最前。
- `PlaceSearchService`：`LocalPlaceSearchService` 用 MapKit `MKLocalSearch`（免費、免金鑰），沒有定位時以日本全境搜尋；有定位時偏向附近。
  地址組成日本習慣順序（〒郵遞區號 都道府縣 市區町村 町名番地）。`CurrentLocationProvider` 一次性取位置，沒權限就略過。
- 畫面：`PlacesView`（列表 + 新增）、`PlaceSearchView`（搜尋 → 點一下存）、`PlaceEditorView`（自己輸入名稱／日文地址／類型／備註；改了地址會清掉舊座標，導航時重新以地址查）、
  `PlaceDetailView`（帶我去＝設定的地圖 App、地址給司機看＝StaffDisplay「ここまでお願いします」、打電話、修改、刪除）。

### M6 補充：旅程分層、地圖選擇、ChatGPT 匯入行程
- `Trip`（名稱、日期）為第一層，`Place.tripId` 掛在旅程下；`Place` 另有 `japaneseName`（給司機看）、`dayLabel`（第幾天）、`sortOrder`。
  `PlaceStore` 同時管旅程與地點，刪旅程連帶刪地點；舊版沒有 tripId 的地點自動歸到「我的地點」。
- 「帶我去」每次都跳出地圖選單（設定裡的預設排第一）：Apple 永遠可用；Google 沒裝改開網頁版 `google.com/maps/dir/?api=1&destination=`；Yahoo! カーナビ 需安裝且需要座標。
- `ChatGPTTripPrompt` + `TripImportParser`：格式 `行程 | 名稱 | 開始 | 結束`、`天 | 第N天 | 日期 | 主題`、`地點 | 中文名 | 日文名 | 日文地址 | 類型 | 備註`。
  匯入後 `TripPlacesView` 在背景用 `PlaceGeocoder`（CLGeocoder → MKLocalSearch）補座標。

## 附錄 I：溝通助手擴充（場面分類）

- `Phrase.scene`：同一分類下再分「場面」（飯店：入住／住宿中／客房服務／早餐／退房／遇到問題…），共 7 類 34 個場面 304 句，資料在 `Resources/Phrases/phrases.json`（由對話中的 Python 產生器一次寫入，之後直接編輯 JSON 即可）。
- `PhraseListView` 與 `EmergencyView` 用 `CategoryChipBar` 切換場面，預設選第一個場面；「全部」時依場面分段顯示。
- 找商品頁引用的 id（shop-have-this 等）維持不變。

## 附錄 J：Apple Intelligence 與「我想問問題」

- `AppleIntelligenceAIService`（iOS 26+，`FoundationModels`）：`@Generable` 結構化輸出整理菜單（日文、中文、拼音、價格、分類、選項）、翻譯；商品／收據需要看圖，回白話錯誤請改用自己的伺服器。
  `AppleIntelligence.availability` 把不可用原因翻成白話（裝置不支援／未開啟／模型下載中／iOS 版本不夠）。
- `AIProviderKind.appleIntelligence`；`SettingsStore` 第一次啟動且裝置支援時預設選它；不可用時 `effectiveAIProvider` 退回未啟用。
- 「我想問問題」（首頁第五張卡）：`AssistantChat` 用 `LanguageModelSession` 多輪對話，角色設定在 `AppleIntelligence.travelAssistantInstructions`（日本旅遊／商品助手、對長輩說話、短句、沒連網要提醒）。
  對話太長（`exceededContextWindowSize`）自動重開一段。回答可用 `SpeechService` 唸出（zh-TW）。
- 側滑返回：`SwipeBackEnabler.swift` 讓 `UINavigationController` 在隱藏系統導覽列時仍可用 interactivePopGesture。

## 附錄 K：旅程的時間表／地點／推薦／地圖／分享

- `ItineraryStop`（哪一天、哪個地點）與 `Place` 分開：同一地點多天出現只存一份。`PlaceStore.importItinerary` 依 `dedupeKey`（日文名優先）合併；舊資料自動遷移。
- `Place.isRecommendation` + `recommendationReason`：ChatGPT 提示文字新增「推薦 | …」行（行程外、附近值得去的 5–10 個）；`addRecommendationToItinerary` 可加進行程。
- `TripPlacesView` 上方分類列：時間表／會去的地點／推薦景點；「看地圖」→ `TripMapView`（SwiftUI `Map`，Apple MapKit，免金鑰）：我的位置、要去的（藍）、推薦（綠）、點大頭針 → 地點頁。
- 分享：`TripPackage`（旅程＋地點＋站點 JSON，副檔名 .jptrip，UTType `com.linzihao.japantravelassistant.trip`）。`ShareLink` 走 AirDrop／LINE；收到檔案由 `AppRouter.handle(url)` 解析 → `TripReceiveView` 確認 → `importPackage`（同 id 更新、否則新增）。
- App icon：`Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png`（單一 1024 尺寸、無透明）。
