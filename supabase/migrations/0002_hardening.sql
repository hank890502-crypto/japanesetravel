-- =====================================================================
-- 日本自由行旅遊助手 — 0002 安全強化
-- 用法：Supabase Dashboard → SQL Editor → 貼上整份 → Run
-- 前提：已經執行過 0001_initial.sql。這份可以重複執行（每一段都是 create or replace / drop if exists）。
--
-- 內容：
--   1. create_room 移除「指定代碼」參數（任何人都能用它關掉別人的房間、搶走代碼），並加上建房節流
--   2. join_room / create_room 稱呼一律截到 30 字
--   3. 點餐（menu_selections）只能寫進「開著且未過期」的房間
--   4. variant_key（選項組合鍵）由資料庫統一產生：小寫 UUID 排序後用「,」連接
--   5. 家人只能改菜的翻譯／備註，不能改價格、菜名；成員不能把自己改成房主
--   6. cleanup_expired_rooms()：刪掉過期／關閉超過 7 天的房間；有 pg_cron 就每天自動跑
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1 + 2. create_room / join_room
-- ---------------------------------------------------------------------
drop function if exists public.create_room(text, text, text);
drop function if exists public.create_room(text, text);

create or replace function public.create_room(p_name text, p_display_name text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_room public.dining_rooms;
  v_member public.room_members;
begin
  if v_uid is null then
    raise exception 'not_authenticated';
  end if;

  -- 節流：同一個人同時最多 5 個開著的房間、一小時最多建 20 次（擋住用公開金鑰灌資料的腳本）
  if (select count(*) from public.dining_rooms
      where host_user_id = v_uid and status = 'open' and expires_at > now()) >= 5 then
    raise exception 'too_many_open_rooms';
  end if;
  if (select count(*) from public.dining_rooms
      where host_user_id = v_uid and created_at > now() - interval '1 hour') >= 20 then
    raise exception 'room_rate_limited';
  end if;

  insert into public.dining_rooms (name, room_code, host_user_id)
  values (coalesce(nullif(left(trim(p_name), 60), ''), '一起點餐'), public.generate_room_code(), v_uid)
  returning * into v_room;

  insert into public.room_members (room_id, user_id, display_name, is_host)
  values (v_room.id, v_uid, coalesce(nullif(left(trim(p_display_name), 30), ''), '房主'), true)
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
  values (v_room.id, v_uid, coalesce(nullif(left(trim(p_display_name), 30), ''), '家人'), v_room.host_user_id = v_uid)
  on conflict (room_id, user_id) do update set display_name = excluded.display_name
  returning * into v_member;

  return jsonb_build_object('room', to_jsonb(v_room), 'member', to_jsonb(v_member));
end $$;

-- 只有登入（含匿名登入）的人可以呼叫；沒登入的 anon 角色不行
revoke all on function public.create_room(text, text) from public, anon;
revoke all on function public.join_room(text, text) from public, anon;
grant execute on function public.create_room(text, text) to authenticated;
grant execute on function public.join_room(text, text) to authenticated;

-- ---------------------------------------------------------------------
-- 3. 點餐只能寫進開著且未過期的房間；成員與菜也必須屬於同一個房間
-- ---------------------------------------------------------------------
drop policy if exists "selections own write" on public.menu_selections;
create policy "selections own write" on public.menu_selections
  for all
  using (
    exists (select 1 from public.room_members m
            where m.id = menu_selections.member_id and m.user_id = auth.uid())
  )
  with check (
    exists (select 1 from public.room_members m
            where m.id = menu_selections.member_id
              and m.user_id = auth.uid()
              and m.room_id = menu_selections.room_id)
    and exists (select 1 from public.dining_rooms r
                where r.id = menu_selections.room_id
                  and r.status = 'open'
                  and r.expires_at > now())
    and exists (select 1 from public.menu_items i
                where i.id = menu_selections.menu_item_id
                  and i.room_id = menu_selections.room_id)
  );

-- ---------------------------------------------------------------------
-- 4. variant_key 由資料庫統一產生（App 與網頁版也用同樣規則，任一端算錯都不會拆成兩行）
-- ---------------------------------------------------------------------
create or replace function public.menu_selections_normalize_variant_key()
returns trigger language plpgsql as $$
begin
  new.option_ids := coalesce(new.option_ids, '{}');
  new.variant_key := coalesce(
    (select string_agg(x::text, ',' order by x) from unnest(new.option_ids) as x),
    ''
  );
  return new;
end $$;

drop trigger if exists menu_selections_normalize_variant_key on public.menu_selections;
create trigger menu_selections_normalize_variant_key
  before insert or update on public.menu_selections
  for each row execute function public.menu_selections_normalize_variant_key();

-- 把既有的列改成新格式（舊 App 寫的是大寫加「+」）。若剛好撞到重複列就略過，房間 48 小時後會過期。
do $$
begin
  update public.menu_selections set option_ids = option_ids where variant_key <> '';
exception when unique_violation then
  raise notice '有舊的重複點餐列，略過不改（房間過期後會自動清掉）';
end $$;

-- ---------------------------------------------------------------------
-- 5. 家人只能改翻譯／備註；成員不能把自己改成房主
--    （RLS 沒辦法限制欄位，所以用 BEFORE UPDATE trigger 比對新舊值；用 42501 讓 App 認得是權限問題）
-- ---------------------------------------------------------------------
create or replace function public.menu_items_guard_member_update()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if public.is_room_host(old.room_id) then
    return new;
  end if;
  if new.id <> old.id
     or new.menu_id <> old.menu_id
     or new.room_id <> old.room_id
     or new.section_id is distinct from old.section_id
     or new.japanese_name <> old.japanese_name
     or new.price is distinct from old.price
     or new.currency <> old.currency
     or new.is_recommended <> old.is_recommended
     or new.sort_order <> old.sort_order
     or new.source_confidence is distinct from old.source_confidence
     or new.source_image_path is distinct from old.source_image_path
     or new.created_at <> old.created_at then
    raise exception 'only_host_can_edit_item' using errcode = '42501';
  end if;
  return new;
end $$;

drop trigger if exists menu_items_guard_member_update on public.menu_items;
create trigger menu_items_guard_member_update
  before update on public.menu_items
  for each row execute function public.menu_items_guard_member_update();

create or replace function public.room_members_guard_update()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.id <> old.id
     or new.room_id <> old.room_id
     or new.user_id <> old.user_id
     or new.is_host <> old.is_host
     or new.created_at <> old.created_at then
    if not public.is_room_host(old.room_id) then
      raise exception 'only_host_can_change_member' using errcode = '42501';
    end if;
  end if;
  new.display_name := coalesce(nullif(left(trim(new.display_name), 30), ''), old.display_name);
  return new;
end $$;

drop trigger if exists room_members_guard_update on public.room_members;
create trigger room_members_guard_update
  before update on public.room_members
  for each row execute function public.room_members_guard_update();

-- ---------------------------------------------------------------------
-- 6. 清理：過期超過 7 天、或關閉且建立超過 7 天的房間整個刪掉（成員、菜單、點餐會 cascade 一起刪）
-- ---------------------------------------------------------------------
create or replace function public.cleanup_expired_rooms()
returns integer language plpgsql security definer set search_path = public as $$
declare
  v_count integer;
begin
  with deleted as (
    delete from public.dining_rooms
    where expires_at < now() - interval '7 days'
       or (status = 'closed' and created_at < now() - interval '7 days')
    returning 1
  )
  select count(*) into v_count from deleted;
  return v_count;
end $$;
-- 只讓排程（postgres 角色）跑，App 與網頁不能呼叫
revoke all on function public.cleanup_expired_rooms() from public, anon, authenticated;

-- 有 pg_cron（Dashboard → Database → Extensions 開啟）就每天台灣時間早上 4:30 跑一次；沒有也不會報錯
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    if exists (select 1 from cron.job where jobname = 'cleanup-expired-rooms') then
      perform cron.unschedule('cleanup-expired-rooms');
    end if;
    perform cron.schedule('cleanup-expired-rooms', '30 20 * * *', 'select public.cleanup_expired_rooms()');
    raise notice 'pg_cron：已排程 cleanup-expired-rooms（每天 UTC 20:30 = 台灣 04:30）';
  else
    raise notice 'pg_cron 尚未啟用：到 Dashboard → Database → Extensions 開啟 pg_cron 後再執行一次這份 SQL，就會自動排程；或手動執行 select public.cleanup_expired_rooms();';
  end if;
exception when others then
  raise notice 'pg_cron 排程失敗（%），可稍後手動執行 select public.cleanup_expired_rooms();', sqlerrm;
end $$;
