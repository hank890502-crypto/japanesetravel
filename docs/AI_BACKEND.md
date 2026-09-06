# AI 後端介面（「自己的伺服器」）

App 永遠不放 AI 金鑰。要用 AI 時，App 只會呼叫「你自己的伺服器」，由伺服器去呼叫 OpenAI / Gemini / Claude。
App 端實作在 `Services/AI/RemoteAIService.swift`；設定頁選「自己的伺服器」並填入網址即可。

## 端點（全部 POST，JSON 進、JSON 出，UTF-8）

基底網址例如 `https://xxxx.supabase.co/functions/v1/ai`。App 會在後面接路徑：

### `menu/analyze` — 整理菜單
請求：
```json
{ "lines": ["若どり唐揚げ ¥540", "手羽先 430円"], "imageBase64": "…(可省略)" }
```
回應：
```json
{
  "restaurantName": "酒津屋",
  "items": [
    {
      "japanese": "若どり唐揚げ", "chinese": "日式炸嫩雞", "reading": "wakadori karaage", "price": 540,
      "section": "揚げ物", "sectionChinese": "炸物", "note": "外酥內嫩",
      "options": [ { "group": "份量", "japanese": "大盛り", "chinese": "大份", "priceDelta": 150 } ]
    }
  ]
}
```
除了 `japanese` 之外都可省略。App 會把結果合併進目前的菜單（日文名對得上的更新，對不上的新增）。

### `translate`
請求 `{ "text": "手羽先", "target": "zh-Hant" }` → 回應 `{ "translated": "雞翅", "reading": "tebasaki" }`

### `product/analyze`
請求 `{ "imageBase64": "…" }` → 回應 `{ "productName": "…", "chineseName": "…", "price": 980, "notes": "…" }`

### `receipt/analyze`
請求 `{ "imageBase64": "…" }` → 回應 `{ "storeName": "…", "total": 1510, "lines": [ { "name": "…", "price": 540, "quantity": 1 } ] }`

錯誤：回非 2xx 即可，App 會顯示白話訊息。照片由 App 先縮到 1280px、JPEG 70%。

## 用 Supabase Edge Function 架（免費方案可用）

範本在 `supabase/functions/ai/index.ts`。步驟：
1. 安裝 Supabase CLI：`brew install supabase/tap/supabase`，`supabase login`，`supabase link --project-ref 你的專案ref`。
2. 設定金鑰（只在伺服器）：`supabase secrets set OPENAI_API_KEY=sk-...`（或 `GEMINI_API_KEY` / `ANTHROPIC_API_KEY`，範本預設用 OpenAI，改幾行就能換）。
3. 部署：`supabase functions deploy ai --no-verify-jwt`
4. App 設定頁 → AI 幫手 → 自己的伺服器 → 網址填 `https://你的專案ref.supabase.co/functions/v1/ai`。

範本目前是最小可用版本：把 App 送來的文字／照片組成提示詞、要求模型輸出上面的 JSON、驗證後回傳。
之後想加「只允許自己的 App 呼叫」，可以在函式裡檢查 Supabase 匿名登入的 JWT（App 端加上 Authorization header）。
