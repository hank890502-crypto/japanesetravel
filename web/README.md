# Web Guest（沒裝 App 的家人用 Safari 點餐）

`web/guest/` 是一個純靜態網頁，直接連同一個 Supabase，資料表、權限規則、即時同步都和 iOS App 共用，
所以 App 建的房間，網頁可以加入；網頁點的東西，房主的 App 會即時看到。

## 本機試跑

1. 複製 `web/guest/config.example.js` 為 `web/guest/config.js`，填入和 `Config/Secrets.xcconfig` 一樣的網址與 publishable key。
2. 在專案根目錄執行：`python3 -m http.server 8080 --directory web/guest`
3. 手機和電腦連同一個 Wi-Fi，用手機 Safari 打開 `http://<你的電腦 IP>:8080/?code=房間代碼`。

## 正式上線（免費）

放到任何靜態空間即可，例如 GitHub Pages、Cloudflare Pages、Netlify：
1. 把 `web/guest/` 整個資料夾上傳（含填好的 `config.js`；publishable key 本來就是公開的）。
2. 拿到網址，例如 `https://你的帳號.github.io/jptravel/`。
3. 在 App 的 `Config/Secrets.xcconfig` 加一行 `WEB_GUEST_URL = https:/$()/你的帳號.github.io/jptravel/`。
   之後 App 的 QR Code 與分享會改用 `https://.../?code=XXXX`：用 iPhone 內建相機掃也能開；有裝 App 的人在網頁按「打開 App」。

## 之後有付費開發者帳號時

加上 Universal Links（Associated Domains + 網站上的 `apple-app-site-association`），掃 https 連結會直接開 App，不用經過網頁。
App 端 `DeepLinkParser` 已經支援 `https://<domain>/room/CODE` 與 `?code=` 兩種格式，不需改程式。
