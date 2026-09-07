// Supabase Edge Function：日本旅遊助手的 AI 後端（最小可用範本）。
// 路徑：POST /functions/v1/ai/menu/analyze、/translate、/product/analyze、/receipt/analyze
// 金鑰只在這裡（supabase secrets set OPENAI_API_KEY=...），App 端沒有任何金鑰。
// 預設用 OpenAI 的 Responses API（支援圖片）；要換 Gemini / Claude 只需改 callModel()。
//
// 呼叫者驗證：設定 APP_TOKEN（supabase secrets set APP_TOKEN=一串自己想的密碼）後，
// 只接受 header X-App-Token 與它相同的請求；App 的「設定 → AI 幫手 → 伺服器密碼」填同一串即可。
// 沒設定 APP_TOKEN 時任何人拿到網址都能呼叫並燒你的額度，正式部署請務必設定。

const OPENAI_API_KEY = Deno.env.get("OPENAI_API_KEY");
const MODEL = Deno.env.get("AI_MODEL") ?? "gpt-4o-mini";
const APP_TOKEN = Deno.env.get("APP_TOKEN");

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-app-token",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json", ...CORS } });

/// 固定時間比對，不讓人用回應時間猜密碼。
function tokenMatches(provided: string | null, expected: string): boolean {
  const a = new TextEncoder().encode(provided ?? "");
  const b = new TextEncoder().encode(expected);
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a[i] ^ b[i];
  return diff === 0;
}

async function callModel(instructions: string, userText: string, imageBase64?: string): Promise<string> {
  if (!OPENAI_API_KEY) throw new Error("OPENAI_API_KEY not set");
  const content: unknown[] = [{ type: "input_text", text: userText }];
  if (imageBase64) content.push({ type: "input_image", image_url: `data:image/jpeg;base64,${imageBase64}` });
  const res = await fetch("https://api.openai.com/v1/responses", {
    method: "POST",
    headers: { Authorization: `Bearer ${OPENAI_API_KEY}`, "Content-Type": "application/json" },
    body: JSON.stringify({ model: MODEL, instructions, input: [{ role: "user", content }], text: { format: { type: "json_object" } } }),
  });
  if (!res.ok) throw new Error(`OpenAI ${res.status}: ${await res.text()}`);
  const data = await res.json();
  return data.output_text ?? data.output?.[0]?.content?.[0]?.text ?? "{}";
}

const MENU_PROMPT = `你是日本餐廳菜單的翻譯與整理助手，服務對象是不懂日文的台灣家庭。
根據使用者提供的菜單文字（與照片，若有）輸出 JSON：
{"restaurantName": string|null, "items": [{"japanese": string, "chinese": string, "reading": string, "price": number|null,
 "section": string|null, "sectionChinese": string|null, "note": string|null,
 "options": [{"group": string, "japanese": string, "chinese": string, "priceDelta": number}]}]}
規則：japanese 照菜單原文不要改字；chinese 用台灣人一看就懂的繁體中文；reading 用平文式羅馬拼音；
price 只寫數字（含稅價優先）；一定要分類（菜單沒有就依類型分）；份量、套餐升級、加價選項放進 options，priceDelta 是相對基本價的加減；
直排菜單由右往左讀；只輸出 JSON。`;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: CORS });
  if (req.method !== "POST") return json({ error: "POST only" }, 405);

  // 共享密鑰：有設定 APP_TOKEN 才檢查；比對失敗一律 401，不透露原因
  if (APP_TOKEN && !tokenMatches(req.headers.get("x-app-token"), APP_TOKEN)) {
    return json({ error: "unauthorized" }, 401);
  }

  const path = new URL(req.url).pathname.replace(/^\/ai\/?/, "").replace(/^\/functions\/v1\/ai\/?/, "");
  let body: Record<string, unknown>;
  try { body = await req.json(); } catch { return json({ error: "invalid json" }, 400); }

  try {
    switch (path) {
      case "menu/analyze": {
        const lines = Array.isArray(body.lines) ? (body.lines as string[]).join("\n") : "";
        const text = await callModel(MENU_PROMPT, `菜單文字：\n${lines || "（沒有文字，請看照片）"}`, body.imageBase64 as string | undefined);
        const parsed = JSON.parse(text);
        if (!Array.isArray(parsed.items)) throw new Error("model returned no items");
        return json(parsed);
      }
      case "translate": {
        const text = await callModel(
          `把日文翻成繁體中文（台灣用語），並給平文式羅馬拼音。只輸出 JSON：{"translated": string, "reading": string}`,
          String(body.text ?? ""));
        return json(JSON.parse(text));
      }
      case "product/analyze": {
        const text = await callModel(
          `辨識照片中的日本商品。只輸出 JSON：{"productName": string|null, "chineseName": string|null, "price": number|null, "notes": string|null}，notes 用繁體中文一句話說明用途或口味。`,
          "請辨識這個商品", body.imageBase64 as string | undefined);
        return json(JSON.parse(text));
      }
      case "receipt/analyze": {
        const text = await callModel(
          `讀取日本收據。只輸出 JSON：{"storeName": string|null, "total": number|null, "lines": [{"name": string, "price": number|null, "quantity": number|null}]}`,
          "請整理這張收據", body.imageBase64 as string | undefined);
        return json(JSON.parse(text));
      }
      default:
        return json({ error: `unknown path: ${path}` }, 404);
    }
  } catch (err) {
    console.error(err);
    return json({ error: String(err) }, 500);
  }
});
