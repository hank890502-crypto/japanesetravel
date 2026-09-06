// 複製成 config.js 並填入你的 Supabase 專案設定（與 App 的 Secrets.xcconfig 相同）。
// publishable key 是公開金鑰，安全性靠資料庫的權限規則，可以放在網頁裡。
window.GUEST_CONFIG = {
  supabaseUrl: "https://your-project-ref.supabase.co",
  supabaseAnonKey: "sb_publishable_xxx",
  appScheme: "jptravel",
};
