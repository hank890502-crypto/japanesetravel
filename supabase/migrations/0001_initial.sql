-- =====================================================================
-- 日本自由行旅遊助手 — Supabase 初始 schema
-- 用法：Supabase Dashboard → SQL Editor → 貼上整份 → Run
-- 前提：Authentication → Sign In / Providers → 開啟 "Anonymous sign-ins"
-- =====================================================================

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------
-- 共用：updated_at 自動更新
-- ---------------------------------------------------------------------
create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end $$;

-- ---------------------------------------------------------------------
-- Trips（第一版只保留資料表，UI 之後再做）
-- ---------------------------------------------------------------------
create table public.trips (
  id              uuid primary key default gen_random_uuid(),
  owner_user_id   uuid not null references auth.users(id) on delete cascade,
  name            text not null,
  start_date      date,
  end_date        date,
  created_at      timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- Dining rooms
-- ---------------------------------------------------------------------
create table public.dining_rooms (
  id              uuid primary key default gen_random_uuid(),
  trip_id         uuid references public.trips(id) on delete set null,
  name            text not null,
  room_code       text not null,
  host_user_id    uuid not null references auth.users(id) on delete cascade,
  status          text not null default 'open' check (status in ('open', 'closed')),
  created_at      timestamptz not null default now(),
  expires_at      timestamptz not null default (now() + interval '48 hours')
);
create unique index dining_rooms_open_code_idx on public.dining_rooms (room_code) where status = 'open';

-- ---------------------------------------------------------------------
-- Room members（一台裝置在同一房間只會有一位成員）
-- ---------------------------------------------------------------------
create table public.room_members (
  id              uuid primary key default gen_random_uuid(),
  room_id         uuid not null references public.dining_rooms(id) on delete cascade,
  user_id         uuid not null references auth.users(id) on delete cascade,
  display_name    text not null check (char_length(display_name) between 1 and 30),
  is_host         boolean not null default false,
  created_at      timestamptz not null default now(),
  unique (room_id, user_id)
);
create index room_members_room_idx on public.room_members (room_id);
create index room_members_user_idx on public.room_members (user_id);

-- ---------------------------------------------------------------------
-- Menus（一個房間可以有多份菜單：主菜單、飲料單）
-- ---------------------------------------------------------------------
create table public.menus (
  id                 uuid primary key default gen_random_uuid(),
  room_id            uuid not null references public.dining_rooms(id) on delete cascade,
  restaurant_name    text,
  created_by_user_id uuid references auth.users(id) on delete set null,
  created_at         timestamptz not null default now()
);
create index menus_room_idx on public.menus (room_id);

create table public.menu_sections (
  id              uuid primary key default gen_random_uuid(),
  menu_id         uuid not null references public.menus(id) on delete cascade,
  room_id         uuid not null references public.dining_rooms(id) on delete cascade, -- 反正規化，方便 RLS 與 realtime filter
  name_japanese   text not null,
  name_chinese    text,
  sort_order      integer not null default 0
);
create index menu_sections_menu_idx on public.menu_sections (menu_id);

create table public.menu_items (
  id                 uuid primary key default gen_random_uuid(),
  menu_id            uuid not null references public.menus(id) on delete cascade,
  room_id            uuid not null references public.dining_rooms(id) on delete cascade, -- 反正規化
  section_id         uuid references public.menu_sections(id) on delete set null,
  japanese_name      text not null,
  chinese_name       text,
  reading            text,
  description        text,
  price              numeric(10, 2),
  currency           text not null default 'JPY',
  is_recommended     boolean not null default false,
  sort_order         integer not null default 0,
  source_confidence  real,
  source_image_path  text,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);
create index menu_items_menu_idx on public.menu_items (menu_id);
create index menu_items_room_idx on public.menu_items (room_id);
create trigger menu_items_set_updated_at before update on public.menu_items
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------
-- Menu item options：份量、套餐升級、配料。同一 group_name 內單選，price_delta 相對基本價。
-- ---------------------------------------------------------------------
create table public.menu_item_options (
  id              uuid primary key default gen_random_uuid(),
  menu_item_id    uuid not null references public.menu_items(id) on delete cascade,
  room_id         uuid not null references public.dining_rooms(id) on delete cascade, -- 反正規化
  group_name      text not null,
  name_japanese   text not null,
  name_chinese    text,
  price_delta     numeric(10, 2) not null default 0,
  sort_order      integer not null default 0
);
create index menu_item_options_item_idx on public.menu_item_options (menu_item_id);
create index menu_item_options_room_idx on public.menu_item_options (room_id);

-- ---------------------------------------------------------------------
-- Menu selections：每位成員 × 每個品項 × 選項組合 一列（核心設計，避免共用 quantity）
-- variant_key = 排序後的 option id 以 + 連接；沒有選項為空字串
-- ---------------------------------------------------------------------
create table public.menu_selections (
  id              uuid primary key default gen_random_uuid(),
  room_id         uuid not null references public.dining_rooms(id) on delete cascade,
  member_id       uuid not null references public.room_members(id) on delete cascade,
  menu_item_id    uuid not null references public.menu_items(id) on delete cascade,
  option_ids      uuid[] not null default '{}',
  variant_key     text not null default '',
  quantity        integer not null default 0 check (quantity >= 0 and quantity <= 99),
  note            text,
  updated_at      timestamptz not null default now(),
  unique (room_id, member_id, menu_item_id, variant_key)
);
create index menu_selections_room_idx on public.menu_selections (room_id);
create trigger menu_selections_set_updated_at before update on public.menu_selections
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------
-- Scan records（原始圖片與 OCR 文字；圖片本體放 Storage）
-- ---------------------------------------------------------------------
create table public.scan_records (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references auth.users(id) on delete cascade,
  room_id         uuid references public.dining_rooms(id) on delete set null,
  menu_id         uuid references public.menus(id) on delete set null,
  storage_path    text,
  ocr_text        text,
  created_at      timestamptz not null default now()
);

-- =====================================================================
-- Row Level Security
-- =====================================================================
alter table public.trips            enable row level security;
alter table public.dining_rooms     enable row level security;
alter table public.room_members     enable row level security;
alter table public.menus            enable row level security;
alter table public.menu_sections    enable row level security;
alter table public.menu_items       enable row level security;
alter table public.menu_item_options enable row level security;
alter table public.menu_selections  enable row level security;
alter table public.scan_records     enable row level security;

-- helper：目前使用者是否為房間成員 / 房主
create or replace function public.is_room_member(p_room_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.room_members
    where room_id = p_room_id and user_id = auth.uid()
  );
$$;

create or replace function public.is_room_host(p_room_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.dining_rooms
    where id = p_room_id and host_user_id = auth.uid()
  );
$$;

-- trips：只有擁有者
create policy "trips owner all" on public.trips
  for all using (owner_user_id = auth.uid()) with check (owner_user_id = auth.uid());

-- dining_rooms：成員可讀；房主可改（關房、改名）。建立一律走 create_room()
create policy "rooms member read" on public.dining_rooms
  for select using (public.is_room_member(id));
create policy "rooms host update" on public.dining_rooms
  for update using (host_user_id = auth.uid()) with check (host_user_id = auth.uid());

-- room_members：成員互相可見；自己可改暱稱。加入一律走 join_room()
create policy "members read" on public.room_members
  for select using (public.is_room_member(room_id));
create policy "members update self" on public.room_members
  for update using (user_id = auth.uid()) with check (user_id = auth.uid());

-- menus / sections / items：成員可讀；房主可增刪改；成員可改 items（幫忙翻譯）
create policy "menus member read" on public.menus
  for select using (public.is_room_member(room_id));
create policy "menus host write" on public.menus
  for all using (public.is_room_host(room_id)) with check (public.is_room_host(room_id));

create policy "sections member read" on public.menu_sections
  for select using (public.is_room_member(room_id));
create policy "sections host write" on public.menu_sections
  for all using (public.is_room_host(room_id)) with check (public.is_room_host(room_id));

create policy "items member read" on public.menu_items
  for select using (public.is_room_member(room_id));
create policy "items host write" on public.menu_items
  for all using (public.is_room_host(room_id)) with check (public.is_room_host(room_id));
create policy "items member update" on public.menu_items
  for update using (public.is_room_member(room_id)) with check (public.is_room_member(room_id));

create policy "options member read" on public.menu_item_options
  for select using (public.is_room_member(room_id));
create policy "options host write" on public.menu_item_options
  for all using (public.is_room_host(room_id)) with check (public.is_room_host(room_id));

-- menu_selections：成員可讀整房；只能寫「自己那位成員」的列
create policy "selections member read" on public.menu_selections
  for select using (public.is_room_member(room_id));
create policy "selections own write" on public.menu_selections
  for all
  using (exists (select 1 from public.room_members m where m.id = member_id and m.user_id = auth.uid()))
  with check (exists (select 1 from public.room_members m where m.id = member_id and m.user_id = auth.uid()));

-- scan_records：只有上傳者
create policy "scans owner all" on public.scan_records
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());

-- =====================================================================
-- RPC：建立房間 / 加入房間
-- =====================================================================
create or replace function public.generate_room_code()
returns text language plpgsql as $$
declare
  alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; -- 無 0/O/1/I
  code text;
  i int;
begin
  loop
    code := '';
    for i in 1..6 loop
      code := code || substr(alphabet, 1 + floor(random() * length(alphabet))::int, 1);
    end loop;
    exit when not exists (select 1 from public.dining_rooms where room_code = code and status = 'open');
  end loop;
  return code;
end $$;

-- 回傳 { "room": {...}, "member": {...} }
-- p_code：測試用的指定代碼（例如 0000）；同代碼的舊房間會先被關閉。正式使用時不傳，由系統產生 6 碼。
create or replace function public.create_room(p_name text, p_display_name text, p_code text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_code text;
  v_room public.dining_rooms;
  v_member public.room_members;
begin
  if v_uid is null then
    raise exception 'not_authenticated';
  end if;

  if p_code is not null and length(trim(p_code)) between 4 and 8 then
    v_code := upper(trim(p_code));
    update public.dining_rooms set status = 'closed' where room_code = v_code and status = 'open';
  else
    v_code := public.generate_room_code();
  end if;

  insert into public.dining_rooms (name, room_code, host_user_id)
  values (coalesce(nullif(trim(p_name), ''), '一起點餐'), v_code, v_uid)
  returning * into v_room;

  insert into public.room_members (room_id, user_id, display_name, is_host)
  values (v_room.id, v_uid, coalesce(nullif(trim(p_display_name), ''), '房主'), true)
  returning * into v_member;

  return jsonb_build_object('room', to_jsonb(v_room), 'member', to_jsonb(v_member));
end $$;

create or replace function public.join_room(p_code text, p_display_name text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_room public.dining_rooms;
  v_member public.room_members;
begin
  if v_uid is null then
    raise exception 'not_authenticated';
  end if;

  select * into v_room from public.dining_rooms
  where room_code = upper(trim(p_code)) and status = 'open' and expires_at > now();

  if not found then
    raise exception 'room_not_found';
  end if;

  insert into public.room_members (room_id, user_id, display_name, is_host)
  values (v_room.id, v_uid, coalesce(nullif(trim(p_display_name), ''), '家人'), v_room.host_user_id = v_uid)
  on conflict (room_id, user_id) do update set display_name = excluded.display_name
  returning * into v_member;

  return jsonb_build_object('room', to_jsonb(v_room), 'member', to_jsonb(v_member));
end $$;

grant execute on function public.create_room(text, text, text) to authenticated;
grant execute on function public.join_room(text, text) to authenticated;

-- =====================================================================
-- View：房間彙總（Host 畫面用；security_invoker 讓 RLS 依然生效）
-- =====================================================================
create or replace view public.room_order_summary
with (security_invoker = true) as
select
  s.room_id,
  s.menu_item_id,
  s.variant_key,
  s.option_ids,
  i.japanese_name,
  i.chinese_name,
  i.price,
  i.currency,
  sum(s.quantity)::integer as total_quantity
from public.menu_selections s
join public.menu_items i on i.id = s.menu_item_id
where s.quantity > 0
group by s.room_id, s.menu_item_id, s.variant_key, s.option_ids, i.japanese_name, i.chinese_name, i.price, i.currency;

-- =====================================================================
-- Realtime
-- =====================================================================
alter table public.menu_selections replica identity full;
alter table public.room_members    replica identity full;
alter table public.menu_items      replica identity full;
alter table public.menu_item_options replica identity full;
alter table public.menu_sections   replica identity full;
alter table public.menus           replica identity full;
alter table public.dining_rooms    replica identity full;

alter publication supabase_realtime add table
  public.menu_selections,
  public.room_members,
  public.menu_items,
  public.menu_item_options,
  public.menu_sections,
  public.menus,
  public.dining_rooms;

-- =====================================================================
-- Storage：菜單原始圖片（private bucket，之後用 signed URL）
-- =====================================================================
insert into storage.buckets (id, name, public)
values ('menu-images', 'menu-images', false)
on conflict (id) do nothing;

create policy "menu images owner" on storage.objects
  for all
  using (bucket_id = 'menu-images' and (storage.foldername(name))[1] = auth.uid()::text)
  with check (bucket_id = 'menu-images' and (storage.foldername(name))[1] = auth.uid()::text);
