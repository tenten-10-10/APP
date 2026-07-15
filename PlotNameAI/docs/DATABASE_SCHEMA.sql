-- PlotName AI — Database Schema (PostgreSQL / Supabase)
-- 漫画プロット・ネーム生成アプリのデータベーススキーマ
--
-- 設計方針:
--   * 1ユーザーが複数のプロジェクト(作品)を持つ
--   * 1プロジェクトは StoryBrief(1) / Phase(13) / Page(N) を持つ
--   * 1ページは複数のパネル(コマ)を持つ
--   * 生成ジョブと使用量(クレジット/トークン)を台帳で追跡し、原価とプラン制限を管理する
--
-- すべてのユーザーデータには Row Level Security(RLS)を想定。末尾にポリシー例を記載。

create extension if not exists "pgcrypto";

-- =====================================================================
-- users
-- =====================================================================
create table if not exists users (
  id            uuid primary key default gen_random_uuid(),
  apple_user_id text unique,
  email         text,
  display_name  text,
  plan          text not null default 'free'
                  check (plan in ('free','plus','pro','studio')),
  created_at    timestamptz not null default now()
);

-- =====================================================================
-- projects  (作品)
-- =====================================================================
create table if not exists projects (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references users(id) on delete cascade,
  title         text not null,
  format        text not null default 'manga'
                  check (format in ('manga','webtoon','film','novel','trpg')),
  page_count    int  not null default 35,
  target_reader text,
  tone          jsonb not null default '[]',
  status        text not null default 'draft'
                  check (status in ('draft','planning','naming','done','archived')),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index if not exists idx_projects_user on projects(user_id);

-- =====================================================================
-- story_briefs  (作品の骨格: ログライン / テーマ / 話型 / 主人公)
-- =====================================================================
create table if not exists story_briefs (
  id                uuid primary key default gen_random_uuid(),
  project_id        uuid not null references projects(id) on delete cascade,
  logline           text,
  theme             text,
  save_the_cat_type text
                      check (save_the_cat_type in (
                        'monster_in_the_house','golden_fleece','out_of_the_bottle',
                        'dude_with_a_problem','rites_of_passage','buddy_love',
                        'whydunit','fool_triumphant','institutionalized','superhero')),
  sub_type          text,
  protagonist       jsonb,  -- { name, want, need, flaw }
  antagonist        jsonb,
  world             jsonb,
  created_at        timestamptz not null default now(),
  unique(project_id)
);

-- =====================================================================
-- phases  (13フェイズ構造)
-- =====================================================================
create table if not exists phases (
  id              uuid primary key default gen_random_uuid(),
  project_id      uuid not null references projects(id) on delete cascade,
  phase_number    int  not null check (phase_number between 1 and 13),
  phase_name      text not null,
  summary         text not null,
  function        text,
  emotional_value int  check (emotional_value between -3 and 3),
  pages           int[] not null default '{}',
  must_show       jsonb not null default '[]',
  created_at      timestamptz not null default now(),
  unique(project_id, phase_number)
);
create index if not exists idx_phases_project on phases(project_id);

-- =====================================================================
-- pages  (ページ割り: このページで何が起きるか)
-- =====================================================================
create table if not exists pages (
  id                 uuid primary key default gen_random_uuid(),
  project_id         uuid not null references projects(id) on delete cascade,
  page_number        int  not null,
  phase_number       int,
  page_goal          text,
  reader_emotion     text,
  turning_point      boolean not null default false,
  panel_count        int,
  last_panel_hook    text,
  dialogue_density   text check (dialogue_density in ('low','medium','high')),
  visual_density     text check (visual_density   in ('low','medium','high')),
  why_this_page_exists text,
  created_at         timestamptz not null default now(),
  unique(project_id, page_number)
);
create index if not exists idx_pages_project on pages(project_id);

-- =====================================================================
-- panels  (コマ: 相対座標レイアウト + 演出 + セリフ)
-- =====================================================================
create table if not exists panels (
  id             uuid primary key default gen_random_uuid(),
  page_id        uuid not null references pages(id) on delete cascade,
  panel_number   int  not null,
  layout         jsonb not null,         -- { x, y, w, h } すべて 0..1 の相対座標
  shot           text,                   -- close_up / medium / wide ...
  camera         text,                   -- slightly_low_angle / high_angle ...
  description    text,
  characters     jsonb not null default '[]',
  dialogue       text,
  sfx            text,
  emotion        text,
  image_prompt   text,
  image_asset_id uuid,                   -- ラフ画像生成結果(任意)
  created_at     timestamptz not null default now(),
  unique(page_id, panel_number)
);
create index if not exists idx_panels_page on panels(page_id);

-- =====================================================================
-- generation_jobs  (非同期生成ジョブ: 35P一括ラフ等)
-- =====================================================================
create table if not exists generation_jobs (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid references users(id) on delete cascade,
  project_id    uuid references projects(id) on delete cascade,
  job_type      text not null,          -- classify_genre / generate_phases / generate_page_plan /
                                         -- generate_layout / generate_name / generate_panel_image / critique
  status        text not null default 'queued'
                  check (status in ('queued','running','succeeded','failed','canceled')),
  input         jsonb,
  output        jsonb,
  cost_estimate numeric,
  credits_used  int not null default 0,
  error         text,
  created_at    timestamptz not null default now(),
  completed_at  timestamptz
);
create index if not exists idx_jobs_user   on generation_jobs(user_id);
create index if not exists idx_jobs_status on generation_jobs(status);

-- =====================================================================
-- usage_ledger  (トークン/画像/クレジットの使用台帳: 原価・プラン制限の根拠)
-- =====================================================================
create table if not exists usage_ledger (
  id                 uuid primary key default gen_random_uuid(),
  user_id            uuid references users(id) on delete cascade,
  project_id         uuid references projects(id) on delete set null,
  action             text not null,
  model              text,
  input_tokens       int,
  output_tokens      int,
  image_count        int not null default 0,
  credits_delta      int not null default 0,   -- 付与は正、消費は負
  estimated_cost_usd numeric,
  created_at         timestamptz not null default now()
);
create index if not exists idx_usage_user on usage_ledger(user_id);
create index if not exists idx_usage_created on usage_ledger(created_at);

-- =====================================================================
-- credit_balances  (クレジット残高: usage_ledger の集計を高速化する任意キャッシュ)
-- =====================================================================
create table if not exists credit_balances (
  user_id    uuid primary key references users(id) on delete cascade,
  balance    int not null default 0,
  updated_at timestamptz not null default now()
);

-- =====================================================================
-- updated_at 自動更新トリガ
-- =====================================================================
create or replace function set_updated_at() returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

drop trigger if exists trg_projects_updated on projects;
create trigger trg_projects_updated before update on projects
  for each row execute function set_updated_at();

-- =====================================================================
-- Row Level Security (例)
--   本番では auth.uid() を users.id にマッピングして所有者のみアクセス可能にする。
-- =====================================================================
alter table projects     enable row level security;
alter table story_briefs enable row level security;
alter table phases       enable row level security;
alter table pages        enable row level security;
alter table panels       enable row level security;

-- 例: projects は所有者のみ閲覧/編集可
-- create policy "owner can read projects"  on projects for select using (user_id = auth.uid());
-- create policy "owner can write projects" on projects for all    using (user_id = auth.uid()) with check (user_id = auth.uid());
