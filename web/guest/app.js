// 一起點餐 Web Guest：與 iOS App 共用同一個 Supabase（匿名登入、join_room、即時同步）。
(function () {
  const cfg = window.GUEST_CONFIG;
  if (!cfg || !cfg.supabaseUrl) { document.body.innerHTML = "<main><h1>尚未設定</h1><p>請先建立 config.js。</p></main>"; return; }
  const sb = window.supabase.createClient(cfg.supabaseUrl, cfg.supabaseAnonKey);

  const $ = (id) => document.getElementById(id);
  const state = { session: null, room: null, member: null, members: [], menus: [], sections: [], items: [], options: [], selections: [], group: "__all__", channel: null };
  const COLORS = ["#0a7ad9", "#e8862c", "#2a9d3b", "#8e44ad", "#d63384", "#17a2a2", "#4b5bd6", "#8b5a2b"];

  // ---------- 工具 ----------
  const yen = (n) => n == null ? "" : "¥" + Number(n).toLocaleString("ja-JP", { maximumFractionDigits: 0 });
  const normalizeCode = (s) => (s || "").toUpperCase().replace(/[\s-]/g, "");
  const validCode = (s) => /^[A-Z0-9]{4,8}$/.test(s);
  const variantKey = (ids) => [...ids].map(String).sort().join("+");
  const showError = (id, title, message) => { const el = $(id); el.innerHTML = `<b>${title}</b>${message || ""}`; el.classList.remove("hidden"); };
  const hideError = (id) => $(id).classList.add("hidden");
  const friendly = (err, fallback) => {
    const m = String(err && (err.message || err)).toLowerCase();
    if (m.includes("room_not_found")) return ["找不到這個房間", "請確認代碼有沒有打錯，或請家人再分享一次。"];
    if (m.includes("failed to fetch") || m.includes("network")) return ["沒有網路", "請確認手機的網路連線後再試一次。"];
    return [fallback, "請再試一次。"];
  };

  // ---------- 網址與 App ----------
  function codeFromURL() {
    const u = new URL(location.href);
    const q = u.searchParams.get("code");
    if (q) return normalizeCode(q);
    const m = u.pathname.match(/\/room\/([A-Za-z0-9]+)/);
    return m ? normalizeCode(m[1]) : (u.hash.startsWith("#") ? normalizeCode(u.hash.slice(1)) : "");
  }
  function updateOpenApp(code) {
    $("open-app").href = `${cfg.appScheme || "jptravel"}://join?code=${encodeURIComponent(code || "")}`;
  }

  // ---------- 登入與加入 ----------
  async function ensureUser() {
    const { data: { session } } = await sb.auth.getSession();
    if (session) return session;
    const { data, error } = await sb.auth.signInAnonymously();
    if (error) throw error;
    return data.session;
  }

  async function join() {
    const code = normalizeCode($("code").value);
    const name = ($("name").value || "").trim() || "家人";
    if (!validCode(code)) { showError("join-error", "代碼不對", "房間代碼是 4 到 8 個英文字母或數字。"); return; }
    $("join-btn").disabled = true; $("join-btn").textContent = "加入中…"; hideError("join-error");
    try {
      await ensureUser();
      const { data, error } = await sb.rpc("join_room", { p_code: code, p_display_name: name });
      if (error) throw error;
      localStorage.setItem("displayName", name);
      state.room = data.room; state.member = data.member;
      localStorage.setItem("roomSession", JSON.stringify({ room: data.room, member: data.member }));
      await enterRoom();
    } catch (err) {
      const [t, m] = friendly(err, "無法加入房間");
      showError("join-error", t, m);
    } finally {
      $("join-btn").disabled = false; $("join-btn").textContent = "加入";
    }
  }

  // ---------- 房間資料 ----------
  async function fetchAll() {
    const id = state.room.id;
    const [members, menus, sections, items, options, selections] = await Promise.all([
      sb.from("room_members").select().eq("room_id", id).order("created_at"),
      sb.from("menus").select().eq("room_id", id).order("created_at"),
      sb.from("menu_sections").select().eq("room_id", id).order("sort_order"),
      sb.from("menu_items").select().eq("room_id", id).order("sort_order"),
      sb.from("menu_item_options").select().eq("room_id", id).order("sort_order"),
      sb.from("menu_selections").select().eq("room_id", id),
    ]);
    for (const r of [members, menus, sections, items, options, selections]) if (r.error) throw r.error;
    state.members = members.data; state.menus = menus.data; state.sections = sections.data;
    state.items = items.data; state.options = options.data; state.selections = selections.data;
    render();
  }

  function subscribe() {
    if (state.channel) sb.removeChannel(state.channel);
    const filter = `room_id=eq.${state.room.id}`;
    let timer = null;
    const refetch = () => { clearTimeout(timer); timer = setTimeout(() => fetchAll().catch(() => showError("room-error", "無法同步", "目前無法同步其他人的點餐內容，請確認網路連線。")), 200); };
    state.channel = sb.channel("guest-" + state.room.id);
    for (const table of ["menu_selections", "room_members", "menu_items", "menu_sections", "menu_item_options", "menus"]) {
      state.channel.on("postgres_changes", { event: "*", schema: "public", table, filter }, refetch);
    }
    state.channel.subscribe((status) => { if (status === "SUBSCRIBED") { hideError("room-error"); refetch(); } });
  }

  async function enterRoom() {
    $("join").classList.add("hidden"); $("room").classList.remove("hidden"); $("bar").classList.remove("hidden");
    $("room-name").textContent = state.room.name;
    try { await fetchAll(); } catch (err) { const [t, m] = friendly(err, "無法載入菜單"); showError("room-error", t, m); }
    subscribe();
  }

  function leave() {
    localStorage.removeItem("roomSession");
    if (state.channel) sb.removeChannel(state.channel);
    location.href = location.pathname;
  }

  // ---------- 點餐 ----------
  const mySelections = () => state.selections.filter((s) => s.member_id === state.member.id && s.quantity > 0);
  function myQty(itemId, optionIds) {
    const k = variantKey(optionIds);
    const s = state.selections.find((x) => x.member_id === state.member.id && x.menu_item_id === itemId && x.variant_key === k);
    return s ? s.quantity : 0;
  }
  function unitPrice(item, optionIds) {
    if (item.price == null) return null;
    return Number(item.price) + optionIds.reduce((sum, id) => { const o = state.options.find((x) => x.id === id); return sum + (o ? Number(o.price_delta) : 0); }, 0);
  }
  async function adjust(item, optionIds, delta) {
    const current = myQty(item.id, optionIds);
    const target = Math.max(0, Math.min(99, current + delta));
    if (target === current) return;
    const k = variantKey(optionIds);
    // 樂觀更新
    const idx = state.selections.findIndex((x) => x.member_id === state.member.id && x.menu_item_id === item.id && x.variant_key === k);
    const previous = JSON.parse(JSON.stringify(state.selections));
    if (idx >= 0) state.selections[idx].quantity = target;
    else state.selections.push({ room_id: state.room.id, member_id: state.member.id, menu_item_id: item.id, option_ids: optionIds, variant_key: k, quantity: target });
    render();
    const { error } = await sb.from("menu_selections").upsert(
      { room_id: state.room.id, member_id: state.member.id, menu_item_id: item.id, option_ids: optionIds, variant_key: k, quantity: target },
      { onConflict: "room_id,member_id,menu_item_id,variant_key" }
    );
    if (error) { state.selections = previous; render(); showError("room-error", "點餐沒有送出", "請確認網路連線後再按一次。"); }
  }

  // ---------- 畫面 ----------
  function groups() {
    const out = [];
    for (const menu of state.menus) {
      for (const sec of state.sections.filter((s) => s.menu_id === menu.id)) {
        const its = state.items.filter((i) => i.section_id === sec.id);
        if (its.length) out.push({ id: sec.id, title: sec.name_japanese, subtitle: sec.name_chinese, items: its });
      }
    }
    const loose = state.items.filter((i) => !i.section_id);
    if (loose.length) out.push({ id: "__none__", title: "其他", subtitle: null, items: loose });
    return out;
  }

  function render() {
    // 成員
    $("members").innerHTML = state.members.map((m, i) => `
      <div class="member"><div class="dot" style="background:${COLORS[i % COLORS.length]}">${(m.display_name || "?").slice(0, 1)}${m.is_host ? " ★" : ""}</div>${m.display_name}${m.id === state.member.id ? "（我）" : ""}</div>`).join("");

    // 分類
    const gs = groups();
    if (!gs.some((g) => g.id === state.group)) state.group = gs.length > 1 ? gs[0].id : "__all__";
    const mine = mySelections();
    const countIn = (g) => g.items.reduce((n, it) => n + mine.filter((s) => s.menu_item_id === it.id).reduce((a, s) => a + s.quantity, 0), 0);
    $("chips").classList.toggle("hidden", gs.length <= 1);
    $("chips").innerHTML = [{ id: "__all__", title: "全部", subtitle: null, badge: mine.reduce((a, s) => a + s.quantity, 0) }, ...gs.map((g) => ({ ...g, badge: countIn(g) }))]
      .map((g) => `<button class="chip ${g.id === state.group ? "on" : ""}" data-group="${g.id}">${g.title}${g.badge ? ` (${g.badge})` : ""}${g.subtitle ? `<small>${g.subtitle}</small>` : ""}</button>`).join("");
    $("chips").querySelectorAll(".chip").forEach((b) => b.onclick = () => { state.group = b.dataset.group; render(); });

    // 菜單
    const visible = state.group === "__all__" ? gs : gs.filter((g) => g.id === state.group);
    $("menu").innerHTML = visible.map((g) => `
      ${state.group === "__all__" ? `<div class="section-title">${g.title}${g.subtitle ? `<small>${g.subtitle}</small>` : ""}</div>` : ""}
      ${g.items.map(renderItem).join("")}`).join("");
    $("menu").querySelectorAll("[data-act]").forEach((b) => b.onclick = () => {
      const item = state.items.find((i) => i.id === b.dataset.item);
      const ids = b.dataset.opts ? b.dataset.opts.split("+").filter(Boolean) : [];
      if (b.dataset.act === "choose") openOptions(item);
      else adjust(item, ids, b.dataset.act === "inc" ? 1 : -1);
    });

    // 底部
    const lines = summaryLines();
    const total = lines.reduce((a, l) => a + l.qty, 0);
    const price = lines.every((l) => l.unit != null) && lines.length ? lines.reduce((a, l) => a + l.unit * l.qty, 0) : null;
    $("bar-total").textContent = total ? `總共 ${total} 份` : "還沒有人點";
    $("bar-price").textContent = price != null ? yen(price) : "";
    const myTotal = mine.reduce((a, s) => a + s.quantity, 0);
    const myPrice = mine.every((s) => unitPrice(state.items.find((i) => i.id === s.menu_item_id) || {}, s.option_ids || []) != null) && mine.length
      ? mine.reduce((a, s) => a + unitPrice(state.items.find((i) => i.id === s.menu_item_id), s.option_ids || []) * s.quantity, 0) : null;
    $("bar-mine").textContent = myTotal ? `我點的 ${myTotal} 份` : "";
    $("bar-mine-price").textContent = myPrice != null ? yen(myPrice) : "";
    renderSummary(lines);
  }

  function renderItem(item) {
    const opts = state.options.filter((o) => o.menu_item_id === item.id);
    const mine = mySelections().filter((s) => s.menu_item_id === item.id);
    const trailing = opts.length
      ? `<button class="add" data-act="choose" data-item="${item.id}">＋ 選擇</button>`
      : stepper(item.id, [], myQty(item.id, []));
    const mineRows = opts.length ? mine.map((s) => {
      const names = (s.option_ids || []).map((id) => { const o = state.options.find((x) => x.id === id); return o ? (o.name_chinese || o.name_japanese) : ""; }).filter(Boolean).join("・") || "不加選項";
      return `<div class="mine"><div class="info">我的：${names}<br><small class="zh">每份 ${yen(unitPrice(item, s.option_ids || []))}</small></div>${stepper(item.id, s.option_ids || [], s.quantity)}</div>`;
    }).join("") : "";
    return `<div class="card"><div class="item"><div class="info">
        <div class="ja">${item.japanese_name}</div>
        <div class="zh">${item.chinese_name || "還沒有中文"}</div>
        ${item.description ? `<div class="zh" style="font-size:16px">${item.description}</div>` : ""}
        ${opts.length ? `<div class="opts">可選：${opts.map((o) => `${o.name_chinese || o.name_japanese} ${deltaText(o.price_delta)}`).join("、")}</div>` : ""}
        <div class="price">${item.price != null ? yen(item.price) : "沒有價格"}</div>
      </div>${trailing}</div>${mineRows}</div>`;
  }
  const deltaText = (d) => Number(d) === 0 ? "±0" : (Number(d) > 0 ? "+" : "−") + yen(Math.abs(Number(d)));
  function stepper(itemId, ids, qty) {
    const o = ids.join("+");
    if (!qty) return `<button class="add" data-act="inc" data-item="${itemId}" data-opts="${o}">＋ 點</button>`;
    return `<div class="stepper"><button data-act="dec" data-item="${itemId}" data-opts="${o}" aria-label="減少一份">−</button><span class="n">${qty}</span><button data-act="inc" data-item="${itemId}" data-opts="${o}" aria-label="增加一份">＋</button></div>`;
  }

  // ---------- 選項 ----------
  let modalItem = null, modalChoice = {};
  function openOptions(item) {
    modalItem = item; modalChoice = {};
    $("modal-title").textContent = item.chinese_name ? `${item.chinese_name}（${item.japanese_name}）` : item.japanese_name;
    renderModal(); $("modal").classList.remove("hidden");
  }
  function renderModal() {
    const opts = state.options.filter((o) => o.menu_item_id === modalItem.id);
    const groupsMap = new Map();
    for (const o of opts) { if (!groupsMap.has(o.group_name)) groupsMap.set(o.group_name, []); groupsMap.get(o.group_name).push(o); }
    $("modal-groups").innerHTML = [...groupsMap.entries()].map(([g, os]) => `
      <h2>${g}</h2>
      <div class="choice ${modalChoice[g] ? "" : "on"}" data-g="${g}" data-o=""><span>${modalChoice[g] ? "○" : "●"}</span><span class="name">不用</span></div>
      ${os.map((o) => `<div class="choice ${modalChoice[g] === o.id ? "on" : ""}" data-g="${g}" data-o="${o.id}"><span>${modalChoice[g] === o.id ? "●" : "○"}</span><span class="name">${o.name_chinese || o.name_japanese}<br><small class="zh">${o.name_japanese}</small></span><b>${deltaText(o.price_delta)}</b></div>`).join("")}`).join("");
    $("modal-groups").querySelectorAll(".choice").forEach((c) => c.onclick = () => { if (c.dataset.o) modalChoice[c.dataset.g] = c.dataset.o; else delete modalChoice[c.dataset.g]; renderModal(); });
    const ids = Object.values(modalChoice);
    const p = unitPrice(modalItem, ids);
    $("modal-add").textContent = p != null ? `加一份（${yen(p)}）` : "加一份";
  }
  $("modal-cancel").onclick = () => $("modal").classList.add("hidden");
  $("modal-add").onclick = () => { $("modal").classList.add("hidden"); adjust(modalItem, Object.values(modalChoice), 1); };

  // ---------- 本桌訂單 ----------
  function summaryLines() {
    const lines = [];
    for (const item of state.items) {
      const sels = state.selections.filter((s) => s.menu_item_id === item.id && s.quantity > 0);
      const byVariant = new Map();
      for (const s of sels) { const k = s.variant_key || ""; if (!byVariant.has(k)) byVariant.set(k, []); byVariant.get(k).push(s); }
      for (const [k, group] of byVariant) {
        const optIds = group[0].option_ids || [];
        const names = optIds.map((id) => state.options.find((o) => o.id === id)).filter(Boolean);
        lines.push({
          item, key: k,
          title: names.length ? `${item.japanese_name}（${names.map((o) => o.name_japanese).join("・")}）` : item.japanese_name,
          zh: [item.chinese_name, names.length ? names.map((o) => o.name_chinese || o.name_japanese).join("・") : null].filter(Boolean).join("，"),
          qty: group.reduce((a, s) => a + s.quantity, 0),
          unit: unitPrice(item, optIds),
          who: group.map((s) => { const m = state.members.find((x) => x.id === s.member_id); return `${m ? m.display_name : "?"} ${s.quantity}`; }).join("　"),
        });
      }
    }
    return lines;
  }
  function renderSummary(lines) {
    $("summary-list").innerHTML = lines.length ? lines.map((l) => `
      <div class="summary-line"><div><div class="ja">${l.title}</div><div class="zh">${l.zh}</div><div class="who">${l.who}</div></div>
      <div style="text-align:right"><div style="font-size:26px;font-weight:700">×${l.qty}</div><div class="zh">${l.unit != null ? yen(l.unit * l.qty) : ""}</div></div></div>`).join("")
      : `<p class="muted">還沒有人點東西。</p>`;
  }
  $("show-summary").onclick = () => { $("room").classList.add("hidden"); $("summary").classList.remove("hidden"); window.scrollTo(0, 0); };
  $("back").onclick = () => { $("summary").classList.add("hidden"); $("room").classList.remove("hidden"); };

  // ---------- 啟動 ----------
  $("join-btn").onclick = join;
  $("leave").onclick = leave;
  $("code").addEventListener("input", () => { $("code").value = normalizeCode($("code").value).slice(0, 8); updateOpenApp($("code").value); });
  // 點進格子就全選：直接打字會覆蓋原本的內容，不用先刪。
  // 滑鼠／手指放開時瀏覽器會把游標移到點的位置而取消選取，所以在剛取得焦點的那一次放開要擋掉。
  for (const id of ["code", "name"]) {
    const el = $(id);
    let justFocused = false;
    el.addEventListener("focus", () => { justFocused = true; el.select(); setTimeout(() => { el.select(); }, 0); });
    el.addEventListener("mouseup", (e) => { if (justFocused) { e.preventDefault(); justFocused = false; } });
    el.addEventListener("touchend", () => { justFocused = false; }, { passive: true });
    el.addEventListener("blur", () => { justFocused = false; });
  }
  $("code").addEventListener("keydown", (e) => { if (e.key === "Enter") $("name").focus(); });
  $("name").addEventListener("keydown", (e) => { if (e.key === "Enter") join(); });
  const initialCode = codeFromURL();
  $("code").value = initialCode; updateOpenApp(initialCode);
  $("name").value = localStorage.getItem("displayName") || "";
  // ?name=媽媽 → 直接加入（QR 或連結可以帶名字，少按一步）
  const presetName = new URL(location.href).searchParams.get("name");
  if (initialCode && presetName) { $("name").value = presetName; join(); }
  const saved = localStorage.getItem("roomSession");
  if (saved && !initialCode) {
    try { const s = JSON.parse(saved); if (new Date(s.room.expires_at) > new Date()) { state.room = s.room; state.member = s.member; ensureUser().then(enterRoom); } } catch (_) {}
  }
})();
