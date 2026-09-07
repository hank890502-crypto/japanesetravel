// 一起點餐 Web Guest：與 iOS App 共用同一個 Supabase（匿名登入、join_room、即時同步）。
(function () {
  const cfg = window.GUEST_CONFIG;
  if (!cfg || !cfg.supabaseUrl) { document.body.innerHTML = "<main><h1>尚未設定</h1><p>請先建立 config.js。</p></main>"; return; }
  const sb = window.supabase.createClient(cfg.supabaseUrl, cfg.supabaseAnonKey);

  const $ = (id) => document.getElementById(id);
  const state = { session: null, room: null, member: null, members: [], menus: [], sections: [], items: [], options: [], selections: [], group: "__all__", channel: null, ended: false, expiryTimer: null };
  const COLORS = ["#0a7ad9", "#e8862c", "#2a9d3b", "#8e44ad", "#d63384", "#17a2a2", "#4b5bd6", "#8b5a2b"];
  const MAX_NAME = 30;

  // ---------- 工具 ----------
  // 所有來自資料庫的字串（成員名稱、菜名、分類、選項）都是別人打的，塞進 HTML 前一律跳脫。
  const esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
  const yen = (n) => n == null ? "" : "¥" + Number(n).toLocaleString("ja-JP", { maximumFractionDigits: 0 });
  // 全形英數（Ａ８Ｆ３Ｋ２）折成半形，與 App 的 RoomCodeGenerator.normalize 一致
  const toHalfwidth = (s) => s.replace(/[！-～]/g, (c) => String.fromCharCode(c.charCodeAt(0) - 0xFEE0)).replace(/　/g, " ");
  const normalizeCode = (s) => toHalfwidth(s || "").toUpperCase().replace(/[\s-]/g, "");
  const validCode = (s) => /^[A-Z0-9]{4,8}$/.test(s);
  // 選項組合鍵，與 App（MenuSelection.variantKey）及資料庫 trigger 一致：小寫 UUID 排序後用「,」連接
  const variantKey = (ids) => [...(ids || [])].map((s) => String(s).toLowerCase()).sort().join(",");
  const nameLength = (s) => [...(s || "")].length;
  // 選項 id 比對不分大小寫（資料庫回的是小寫，App 舊版寫入的可能是大寫）
  const optionById = (id) => { const k = String(id).toLowerCase(); return state.options.find((x) => String(x.id).toLowerCase() === k); };
  const showError = (id, title, message) => {
    const el = $(id);
    el.textContent = "";
    const b = document.createElement("b"); b.textContent = title; el.appendChild(b);
    el.appendChild(document.createTextNode(message || ""));
    el.classList.remove("hidden");
  };
  const hideError = (id) => $(id).classList.add("hidden");
  const friendly = (err, fallback) => {
    const m = (String(err && (err.message || err)) + " " + String(err && err.code || "")).toLowerCase();
    if (m.includes("room_not_found")) return ["找不到這個房間", "請確認代碼有沒有打錯，或請家人再分享一次。房間超過兩天也會自動結束。"];
    if (m.includes("display_name_check") || m.includes("check constraint") || m.includes("23514")) return ["稱呼太長了", `請把稱呼改短一點（最多 ${MAX_NAME} 個字）。`];
    if (m.includes("row-level security") || m.includes("permission denied") || m.includes("42501")) return ["你已經不在這個房間裡", "房間可能已經結束。請按最下面的「離開這個房間」，再用代碼重新加入。"];
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

  function saveSession(room, member) {
    state.room = room; state.member = member;
    localStorage.setItem("roomSession", JSON.stringify({ room, member }));
  }

  async function join() {
    const code = normalizeCode($("code").value);
    const name = ($("name").value || "").trim() || "家人";
    if (!validCode(code)) { showError("join-error", "代碼不對", "房間代碼是 4 到 8 個英文字母或數字。"); return; }
    if (nameLength(name) > MAX_NAME) { showError("join-error", "稱呼太長了", `稱呼最多 ${MAX_NAME} 個字，請改短一點。`); return; }
    $("join-btn").disabled = true; $("join-btn").textContent = "加入中…"; hideError("join-error");
    try {
      await ensureUser();
      const { data, error } = await sb.rpc("join_room", { p_code: code, p_display_name: name });
      if (error) throw error;
      localStorage.setItem("displayName", name);
      saveSession(data.room, data.member);
      await enterRoom();
    } catch (err) {
      const [t, m] = friendly(err, "無法加入房間");
      showError("join-error", t, m);
    } finally {
      $("join-btn").disabled = false; $("join-btn").textContent = "加入";
    }
  }

  // 重開網頁時不信任本機存的資料：先向伺服器確認還是成員（join_room 是 upsert，同一個人只會更新稱呼；
  // 身分變了會重新加入；房間關了或過期會回 room_not_found）。失敗就清掉、回到加入頁並預填代碼與稱呼。
  async function restore(saved) {
    if (!saved || !saved.room || !saved.member) return;
    $("code").value = normalizeCode(saved.room.room_code || ""); updateOpenApp($("code").value);
    if (saved.member.display_name) $("name").value = saved.member.display_name;
    if (!(new Date(saved.room.expires_at) > new Date())) { localStorage.removeItem("roomSession"); return; }
    try {
      await ensureUser();
      const { data, error } = await sb.rpc("join_room", { p_code: saved.room.room_code, p_display_name: saved.member.display_name || "家人" });
      if (error) throw error;
      saveSession(data.room, data.member);
      await enterRoom();
    } catch (err) {
      localStorage.removeItem("roomSession");
      const [t, m] = friendly(err, "無法回到上次的房間");
      const gone = String(err && err.message || "").toLowerCase().includes("room_not_found");
      showError("join-error", gone ? "上次的房間已經結束" : t, gone ? "要再一起點餐，請家人再分享一次代碼。" : m);
    }
  }

  // ---------- 房間資料 ----------
  const roomHasEnded = () => !state.room || state.room.status !== "open" || !(new Date(state.room.expires_at) > new Date());

  function endRoom() {
    if (state.ended) return;
    state.ended = true;
    localStorage.removeItem("roomSession");
    if (state.channel) { sb.removeChannel(state.channel); state.channel = null; }
    showError("room-error", "這個房間已經結束", "房間超過兩天會自動結束，或是房主已經關閉。要再一起點餐，請家人再分享一次代碼。");
    render();
  }

  function scheduleExpiry() {
    clearTimeout(state.expiryTimer);
    if (!state.room) return;
    const remaining = new Date(state.room.expires_at) - new Date();
    state.expiryTimer = setTimeout(() => { if (roomHasEnded()) endRoom(); }, Math.max(0, Math.min(remaining, 2147483647)));
  }

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
    // 名單裡沒有我 = 已經不是成員（身分變了、房間被清掉）
    if (!state.members.some((m) => m.id === state.member.id)) { endRoom(); return; }
    render();
  }

  function subscribe() {
    if (state.channel) sb.removeChannel(state.channel);
    const filter = `room_id=eq.${state.room.id}`;
    let timer = null;
    const refetch = () => { clearTimeout(timer); timer = setTimeout(() => fetchAll().catch(() => showError("room-error", "無法同步", "目前無法同步其他人的點餐內容，請確認網路連線。")), 200); };
    // 名稱加上隨機字串：即使同一個分頁重複進出，也不會拆掉還在用的訂閱
    state.channel = sb.channel("guest-" + state.room.id + "-" + Math.random().toString(36).slice(2));
    for (const table of ["menu_selections", "room_members", "menu_items", "menu_sections", "menu_item_options", "menus"]) {
      state.channel.on("postgres_changes", { event: "*", schema: "public", table, filter }, refetch);
    }
    state.channel.subscribe((status) => {
      if (status === "SUBSCRIBED") {
        if (roomHasEnded()) { endRoom(); return; }
        hideError("room-error"); refetch();
      }
    });
  }

  async function enterRoom() {
    $("join").classList.add("hidden"); $("room").classList.remove("hidden"); $("bar").classList.remove("hidden");
    $("room-name").textContent = state.room.name;
    state.ended = false;
    if (roomHasEnded()) { endRoom(); return; }
    scheduleExpiry();
    try { await fetchAll(); } catch (err) { const [t, m] = friendly(err, "無法載入菜單"); showError("room-error", t, m); }
    if (!state.ended) subscribe();
  }

  function leave() {
    localStorage.removeItem("roomSession");
    if (state.channel) sb.removeChannel(state.channel);
    location.href = location.pathname;
  }

  // ---------- 點餐 ----------
  const mySelections = () => state.selections.filter((s) => s.member_id === state.member.id && s.quantity > 0);
  // 一律用 option_ids 重算，不信任資料庫欄位（舊資料可能是另一種格式）
  const keyOf = (s) => variantKey(s.option_ids || []);
  function myQty(itemId, optionIds) {
    const k = variantKey(optionIds);
    const s = state.selections.find((x) => x.member_id === state.member.id && x.menu_item_id === itemId && keyOf(x) === k);
    return s ? s.quantity : 0;
  }
  function unitPrice(item, optionIds) {
    if (item.price == null) return null;
    return Number(item.price) + optionIds.reduce((sum, id) => { const o = optionById(id); return sum + (o ? Number(o.price_delta) : 0); }, 0);
  }
  async function adjust(item, optionIds, delta) {
    if (state.ended || roomHasEnded()) { endRoom(); return; }
    const current = myQty(item.id, optionIds);
    const target = Math.max(0, Math.min(99, current + delta));
    if (target === current) return;
    const k = variantKey(optionIds);
    // 樂觀更新
    const idx = state.selections.findIndex((x) => x.member_id === state.member.id && x.menu_item_id === item.id && keyOf(x) === k);
    const previous = JSON.parse(JSON.stringify(state.selections));
    if (idx >= 0) state.selections[idx].quantity = target;
    else state.selections.push({ room_id: state.room.id, member_id: state.member.id, menu_item_id: item.id, option_ids: optionIds, variant_key: k, quantity: target });
    render();
    const { error } = await sb.from("menu_selections").upsert(
      { room_id: state.room.id, member_id: state.member.id, menu_item_id: item.id, option_ids: optionIds, variant_key: k, quantity: target },
      { onConflict: "room_id,member_id,menu_item_id,variant_key" }
    );
    if (error) {
      state.selections = previous; render();
      const [t, m] = friendly(error, "點餐沒有送出");
      showError("room-error", t, t === "點餐沒有送出" ? "請確認網路連線後再按一次。" : m);
    }
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
    // 成員（全部用 DOM API 建，名稱是別人打的字串）
    const membersEl = $("members");
    membersEl.textContent = "";
    state.members.forEach((m, i) => {
      const wrap = document.createElement("div"); wrap.className = "member";
      const dot = document.createElement("div"); dot.className = "dot"; dot.style.background = COLORS[i % COLORS.length];
      dot.textContent = [...(m.display_name || "?")][0] + (m.is_host ? " ★" : "");
      wrap.appendChild(dot);
      wrap.appendChild(document.createTextNode((m.display_name || "") + (m.id === state.member.id ? "（我）" : "")));
      membersEl.appendChild(wrap);
    });

    // 分類
    const gs = groups();
    if (!gs.some((g) => g.id === state.group)) state.group = gs.length > 1 ? gs[0].id : "__all__";
    const mine = mySelections();
    const countIn = (g) => g.items.reduce((n, it) => n + mine.filter((s) => s.menu_item_id === it.id).reduce((a, s) => a + s.quantity, 0), 0);
    $("chips").classList.toggle("hidden", gs.length <= 1);
    $("chips").innerHTML = [{ id: "__all__", title: "全部", subtitle: null, badge: mine.reduce((a, s) => a + s.quantity, 0) }, ...gs.map((g) => ({ ...g, badge: countIn(g) }))]
      .map((g) => `<button class="chip ${g.id === state.group ? "on" : ""}" data-group="${esc(g.id)}">${esc(g.title)}${g.badge ? ` (${g.badge})` : ""}${g.subtitle ? `<small>${esc(g.subtitle)}</small>` : ""}</button>`).join("");
    $("chips").querySelectorAll(".chip").forEach((b) => b.onclick = () => { state.group = b.dataset.group; render(); });

    // 菜單
    const visible = state.group === "__all__" ? gs : gs.filter((g) => g.id === state.group);
    $("menu").innerHTML = visible.map((g) => `
      ${state.group === "__all__" ? `<div class="section-title">${esc(g.title)}${g.subtitle ? `<small>${esc(g.subtitle)}</small>` : ""}</div>` : ""}
      ${g.items.map(renderItem).join("")}`).join("");
    $("menu").querySelectorAll("[data-act]").forEach((b) => {
      b.disabled = state.ended;
      b.onclick = () => {
        const item = state.items.find((i) => i.id === b.dataset.item);
        const ids = b.dataset.opts ? b.dataset.opts.split(",").filter(Boolean) : [];
        if (b.dataset.act === "choose") openOptions(item);
        else adjust(item, ids, b.dataset.act === "inc" ? 1 : -1);
      };
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
    fitBottomPadding();
  }

  // 底部固定的訂單列比 CSS 預留的高（有「我點的」那一列、iPhone 的 Home 指示條），實際量高度再留空間，
  // 捲到最底時「離開這個房間」與最後一道菜不會被蓋住
  function fitBottomPadding() {
    const bar = $("bar");
    const main = document.querySelector("main");
    if (!bar || !main) return;
    main.style.paddingBottom = bar.classList.contains("hidden") ? "" : (bar.offsetHeight + 24) + "px";
  }

  function renderItem(item) {
    const opts = state.options.filter((o) => o.menu_item_id === item.id);
    const mine = mySelections().filter((s) => s.menu_item_id === item.id);
    const trailing = opts.length
      ? `<button class="add" data-act="choose" data-item="${esc(item.id)}">＋ 選擇</button>`
      : stepper(item.id, [], myQty(item.id, []));
    const mineRows = opts.length ? mine.map((s) => {
      const names = (s.option_ids || []).map((id) => { const o = optionById(id); return o ? (o.name_chinese || o.name_japanese) : ""; }).filter(Boolean).join("・") || "不加選項";
      return `<div class="mine"><div class="info">我的：${esc(names)}<br><small class="zh">每份 ${esc(yen(unitPrice(item, s.option_ids || [])))}</small></div>${stepper(item.id, s.option_ids || [], s.quantity)}</div>`;
    }).join("") : "";
    return `<div class="card"><div class="item"><div class="info">
        <div class="ja">${esc(item.japanese_name)}</div>
        <div class="zh">${esc(item.chinese_name || "還沒有中文")}</div>
        ${item.description ? `<div class="zh" style="font-size:16px">${esc(item.description)}</div>` : ""}
        ${opts.length ? `<div class="opts">可選：${esc(opts.map((o) => `${o.name_chinese || o.name_japanese} ${deltaText(o.price_delta)}`).join("、"))}</div>` : ""}
        <div class="price">${item.price != null ? esc(yen(item.price)) : "沒有價格"}</div>
      </div>${trailing}</div>${mineRows}</div>`;
  }
  const deltaText = (d) => Number(d) === 0 ? "±0" : (Number(d) > 0 ? "+" : "−") + yen(Math.abs(Number(d)));
  function stepper(itemId, ids, qty) {
    const o = esc(variantKey(ids));
    const id = esc(itemId);
    if (!qty) return `<button class="add" data-act="inc" data-item="${id}" data-opts="${o}">＋ 點</button>`;
    return `<div class="stepper"><button data-act="dec" data-item="${id}" data-opts="${o}" aria-label="減少一份">−</button><span class="n">${Number(qty)}</span><button data-act="inc" data-item="${id}" data-opts="${o}" aria-label="增加一份">＋</button></div>`;
  }

  // ---------- 選項 ----------
  let modalItem = null, modalChoice = {};
  function openOptions(item) {
    if (state.ended) return;
    modalItem = item; modalChoice = {};
    $("modal-title").textContent = item.chinese_name ? `${item.chinese_name}（${item.japanese_name}）` : item.japanese_name;
    renderModal(); $("modal").classList.remove("hidden");
  }
  function renderModal() {
    const opts = state.options.filter((o) => o.menu_item_id === modalItem.id);
    const groupsMap = new Map();
    for (const o of opts) { if (!groupsMap.has(o.group_name)) groupsMap.set(o.group_name, []); groupsMap.get(o.group_name).push(o); }
    // 群組名稱是別人打的字串：data-g 用索引，不把字串放進屬性
    const groupList = [...groupsMap.entries()];
    $("modal-groups").innerHTML = groupList.map(([g, os], gi) => `
      <h2>${esc(g)}</h2>
      <div class="choice ${modalChoice[g] ? "" : "on"}" data-g="${gi}" data-o=""><span>${modalChoice[g] ? "○" : "●"}</span><span class="name">不用</span></div>
      ${os.map((o) => `<div class="choice ${modalChoice[g] === o.id ? "on" : ""}" data-g="${gi}" data-o="${esc(o.id)}"><span>${modalChoice[g] === o.id ? "●" : "○"}</span><span class="name">${esc(o.name_chinese || o.name_japanese)}<br><small class="zh">${esc(o.name_japanese)}</small></span><b>${esc(deltaText(o.price_delta))}</b></div>`).join("")}`).join("");
    $("modal-groups").querySelectorAll(".choice").forEach((c) => c.onclick = () => {
      const g = groupList[Number(c.dataset.g)]?.[0];
      if (g == null) return;
      if (c.dataset.o) modalChoice[g] = c.dataset.o; else delete modalChoice[g];
      renderModal();
    });
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
      for (const s of sels) { const k = keyOf(s); if (!byVariant.has(k)) byVariant.set(k, []); byVariant.get(k).push(s); }
      for (const [k, group] of byVariant) {
        const optIds = group[0].option_ids || [];
        const names = optIds.map(optionById).filter(Boolean);
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
      <div class="summary-line"><div><div class="ja">${esc(l.title)}</div><div class="zh">${esc(l.zh)}</div><div class="who">${esc(l.who)}</div></div>
      <div style="text-align:right"><div style="font-size:26px;font-weight:700">×${Number(l.qty)}</div><div class="zh">${l.unit != null ? esc(yen(l.unit * l.qty)) : ""}</div></div></div>`).join("")
      : `<p class="muted">還沒有人點東西。</p>`;
  }
  $("show-summary").onclick = () => { $("room").classList.add("hidden"); $("summary").classList.remove("hidden"); window.scrollTo(0, 0); };
  $("back").onclick = () => { $("summary").classList.add("hidden"); $("room").classList.remove("hidden"); };

  // ---------- 啟動 ----------
  $("join-btn").onclick = join;
  $("leave").onclick = leave;
  $("code").addEventListener("input", () => { $("code").value = normalizeCode($("code").value).slice(0, 8); updateOpenApp($("code").value); });
  $("name").addEventListener("input", () => {
    const chars = [...$("name").value];
    if (chars.length > MAX_NAME) $("name").value = chars.slice(0, MAX_NAME).join("");
    $("name-hint").textContent = [...$("name").value].length >= MAX_NAME ? `稱呼最多 ${MAX_NAME} 個字，已經到上限了。` : `稱呼最多 ${MAX_NAME} 個字。`;
  });
  window.addEventListener("resize", fitBottomPadding);
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
  // ?name=媽媽 → 直接加入（QR 或連結可以帶名字，少按一步）；超過 30 字先截斷
  const presetName = new URL(location.href).searchParams.get("name");
  if (initialCode && presetName) { $("name").value = [...presetName].slice(0, MAX_NAME).join(""); join(); }
  const saved = localStorage.getItem("roomSession");
  if (saved && !initialCode) {
    try { restore(JSON.parse(saved)); } catch (_) { localStorage.removeItem("roomSession"); }
  }
})();
