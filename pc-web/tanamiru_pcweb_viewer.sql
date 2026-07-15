-- タナミル PC/Web 閲覧ビューア バックエンド（読み取り専用・QRペアリング）
-- Supabase プロジェクト lwxpbgbqldhnvcxnyehe の SQL Editor に貼り付けて実行。
-- 追加のみ・既存テーブルには一切触れない。anon キー + SECURITY DEFINER RPC 方式
-- （既存の tanamiru_fetch_borrow_requests と同じ流儀）。

-- 端末/アカウント単位の在庫スナップショット（アプリが丸ごと push）。
create table if not exists public.tanamiru_pcweb_snapshots (
  account_key text primary key,
  payload     jsonb not null default '{}'::jsonb,
  app_version text,
  updated_at  timestamptz not null default now()
);
alter table public.tanamiru_pcweb_snapshots enable row level security;

-- QRペアリングのログインセッション。
--   pair_code  … QRに入る（スマホが読み取って認可）
--   web_secret … PC側だけが保持（token取得に必要。QRが漏れてもセッションは盗めない）
create table if not exists public.tanamiru_pcweb_pairings (
  id            uuid primary key default gen_random_uuid(),
  pair_code     text not null unique,
  web_secret    text not null,
  status        text not null default 'pending' check (status in ('pending','authorized','expired')),
  account_key   text,
  web_token     text,
  label         text,
  created_at    timestamptz not null default now(),
  expires_at    timestamptz not null default (now() + interval '3 minutes'),
  authorized_at timestamptz
);
alter table public.tanamiru_pcweb_pairings enable row level security;
create index if not exists tanamiru_pcweb_pairings_secret_idx on public.tanamiru_pcweb_pairings(web_secret);
create index if not exists tanamiru_pcweb_pairings_token_idx  on public.tanamiru_pcweb_pairings(web_token);

-- 直接アクセスは全面禁止（RLS でポリシー無し）。以下の RPC 経由のみ。
revoke all on public.tanamiru_pcweb_snapshots from anon, authenticated;
revoke all on public.tanamiru_pcweb_pairings  from anon, authenticated;

-- Web: ペアリング作成。QR用の pair_code と、PC側だけが持つ web_secret を返す。
create or replace function public.tanamiru_pcweb_create_pairing(p_label text default null)
returns table(pair_code text, web_secret text)
language plpgsql security definer set search_path = public as $$
declare v_code text; v_secret text;
begin
  v_code   := upper(substr(replace(gen_random_uuid()::text,'-',''),1,12));
  v_secret := replace(gen_random_uuid()::text,'-','') || replace(gen_random_uuid()::text,'-','');
  insert into public.tanamiru_pcweb_pairings(pair_code, web_secret, label)
    values (v_code, v_secret, left(coalesce(p_label,''),200));
  pair_code := v_code; web_secret := v_secret; return next;
end $$;

-- 電話: QRを読み取ってアカウントに束縛。web_token を発行。
create or replace function public.tanamiru_pcweb_authorize(p_pair_code text, p_account_key text)
returns text language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_token text;
begin
  select id into v_id from public.tanamiru_pcweb_pairings
    where pair_code = upper(p_pair_code) and status = 'pending' and expires_at > now()
    for update;
  if v_id is null then return 'invalid'; end if;
  v_token := replace(gen_random_uuid()::text,'-','') || replace(gen_random_uuid()::text,'-','');
  update public.tanamiru_pcweb_pairings
    set status='authorized', account_key=p_account_key, web_token=v_token, authorized_at=now()
    where id = v_id;
  return 'ok';
end $$;

-- Web: web_secret で状態を確認。認可後に web_token を受け取る。
create or replace function public.tanamiru_pcweb_poll(p_web_secret text)
returns table(status text, web_token text)
language plpgsql security definer set search_path = public as $$
begin
  return query
    select p.status,
           case when p.status='authorized' then p.web_token else null end
      from public.tanamiru_pcweb_pairings p
     where p.web_secret = p_web_secret
     limit 1;
end $$;

-- Web: web_token に束縛されたアカウントのスナップショットを取得。
create or replace function public.tanamiru_pcweb_get_snapshot(p_web_token text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_key text; v_payload jsonb;
begin
  select account_key into v_key from public.tanamiru_pcweb_pairings
    where web_token = p_web_token and status='authorized' limit 1;
  if v_key is null then return null; end if;
  select payload into v_payload from public.tanamiru_pcweb_snapshots where account_key = v_key;
  return coalesce(v_payload, '{}'::jsonb);
end $$;

-- 電話: 自分のアカウントのスナップショットを upsert。
create or replace function public.tanamiru_pcweb_push_snapshot(p_account_key text, p_payload jsonb, p_app_version text default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  insert into public.tanamiru_pcweb_snapshots(account_key, payload, app_version, updated_at)
    values (p_account_key, p_payload, p_app_version, now())
  on conflict (account_key) do update
    set payload = excluded.payload, app_version = excluded.app_version, updated_at = now();
end $$;

grant execute on function public.tanamiru_pcweb_create_pairing(text) to anon;
grant execute on function public.tanamiru_pcweb_authorize(text, text) to anon;
grant execute on function public.tanamiru_pcweb_poll(text) to anon;
grant execute on function public.tanamiru_pcweb_get_snapshot(text) to anon;
grant execute on function public.tanamiru_pcweb_push_snapshot(text, jsonb, text) to anon;
