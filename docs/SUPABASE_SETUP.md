# Supabase 設定（M3 多人點餐）

全程免費方案即可，大約 10 分鐘。做完之後，家人用不同手機輸入代碼就能一起點餐。

## 1. 建立專案

1. 打開 https://supabase.com ，用 GitHub 或 Email 註冊、登入。
2. 按 **New project**。
   - Name：隨便取，例如 `japan-travel`
   - Database Password：按 Generate 產生一組，**存起來**（之後幾乎用不到，但不要弄丟）
   - Region：選 **Northeast Asia (Tokyo)**，在日本用最快
3. 按 **Create new project**，等 1～2 分鐘。

## 2. 開啟匿名登入

1. 左邊選單 **Authentication** → **Sign In / Providers**（舊版叫 Providers）。
2. 找到 **Anonymous sign-ins**，打開開關，按 **Save**。

App 不需要帳號密碼，每台手機第一次打開會自動變成一個匿名使用者。

## 3. 建立資料表

1. 左邊選單 **SQL Editor** → **New query**。
2. 用文字編輯器打開專案裡的 `supabase/migrations/0001_initial.sql`，全選、複製、貼到 SQL Editor。
3. 按右下角 **Run**。看到 `Success. No rows returned` 就完成了。

如果出現紅字錯誤，把錯誤訊息整段貼給我。

## 4. 拿網址和金鑰

1. 左邊選單 **Project Settings**（齒輪）→ **API**（新版在 **Data API** 或 **API Keys**）。
2. 記下兩個值：
   - **Project URL**：像 `https://abcdefghijkl.supabase.co`
   - **anon public** 金鑰（新版叫 **publishable key**，`sb_publishable_...` 開頭；舊版是很長的 `eyJ...`）：這是可以放在 App 裡的公開金鑰，安全性靠資料庫的權限規則。

## 5. 填進 App

1. 在 Finder 打開專案的 `Config` 資料夾。
2. 複製 `Secrets.example.xcconfig`，改名為 `Secrets.xcconfig`（同一個資料夾）。
3. 用文字編輯器打開 `Secrets.xcconfig`，改成你的值。**注意網址要寫成 `https:/$()/`**，因為 xcconfig 把 `//` 當註解：

```
SUPABASE_URL = https:/$()/abcdefghijkl.supabase.co
SUPABASE_ANON_KEY = 你的金鑰
```

4. 存檔。這個檔案已經在 `.gitignore`，不會進 Git。
5. 回到 Xcode，**Product → Clean Build Folder**（⇧⌘K），再按 ▶。

## 6. 驗證

- 打開 App → 我要看懂這個 → 看菜單、一起點餐 → 拍菜單 → 用示範菜單或 ChatGPT 匯入 → 下一步 → 建立房間。
- 建立房間頁**沒有出現**「目前沒有連上多人點餐」的紅色提示，代表設定成功。
- 用第二台 iPhone（或同一台先離開房間再加入）輸入代碼，應該看到同一份菜單，兩邊點的東西會即時同步。
- Supabase 網頁的 **Table Editor** 可以看到 `dining_rooms`、`menu_selections` 裡的資料。

## 常見問題

- **建立房間時顯示「無法連上多人點餐」**：檢查步驟 2 匿名登入有沒有打開，以及 `Secrets.xcconfig` 的網址有沒有寫成 `https:/$()/`。
- **加入時顯示「找不到這個房間」**：代碼打錯，或房間已超過 48 小時（自動過期）。
- **改了 Secrets.xcconfig 沒生效**：要 Clean Build Folder 再跑。
