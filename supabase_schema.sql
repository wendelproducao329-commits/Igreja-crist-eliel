-- Igreja Cristã Eliel — esquema inicial para Supabase
-- Execute no SQL Editor de um projeto Supabase novo.
create extension if not exists pgcrypto;

create table if not exists public.ministries (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  slug text not null unique,
  description text not null default '',
  created_at timestamptz not null default now()
);

insert into public.ministries(name, slug) values
('Acolhimento','acolhimento'),
('Intercessão','intercessao'),
('Ação Social','acao-social'),
('Louvor','louvor'),
('Mídia','midia'),
('Projeção','projecao'),
('Jovens','jovens'),
('Infantil','infantil')
on conflict (slug) do nothing;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null default '',
  role text not null default 'leader' check (role in ('pastor','leader')),
  ministry_id uuid references public.ministries(id) on delete set null,
  created_at timestamptz not null default now()
);

create table if not exists public.events (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  description text not null default '',
  starts_at timestamptz not null,
  ministry_id uuid references public.ministries(id) on delete set null,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now()
);

create table if not exists public.news (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  body text not null default '',
  ministry_id uuid references public.ministries(id) on delete set null,
  published boolean not null default false,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now()
);

create table if not exists public.media_items (
  id uuid primary key default gen_random_uuid(),
  title text not null default '',
  media_url text not null,
  media_type text not null check (media_type in ('image','video')),
  ministry_id uuid references public.ministries(id) on delete set null,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now()
);

create or replace function public.is_pastor()
returns boolean language sql stable security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'pastor'
  );
$$;

create or replace function public.my_ministry_id()
returns uuid language sql stable security definer
set search_path = public
as $$
  select ministry_id from public.profiles where id = auth.uid();
$$;

alter table public.profiles enable row level security;
alter table public.ministries enable row level security;
alter table public.events enable row level security;
alter table public.news enable row level security;
alter table public.media_items enable row level security;

-- Perfis: cada usuário lê o próprio perfil; pastores leem todos.
create policy "profile self read" on public.profiles for select
using (id = auth.uid() or public.is_pastor());
create policy "pastors manage profiles" on public.profiles for all
using (public.is_pastor()) with check (public.is_pastor());

-- Ministérios: leitura pública para exibição no site; alterações apenas pastores.
create policy "ministries public read" on public.ministries for select using (true);
create policy "pastors manage ministries" on public.ministries for all
using (public.is_pastor()) with check (public.is_pastor());

-- Eventos: visitantes podem ler; pastores gerenciam tudo; líderes gerenciam o próprio ministério.
create policy "events public read" on public.events for select using (true);
create policy "events scoped insert" on public.events for insert
with check (
  public.is_pastor()
  or (ministry_id = public.my_ministry_id() and created_by = auth.uid())
);
create policy "events scoped update" on public.events for update
using (public.is_pastor() or ministry_id = public.my_ministry_id())
with check (public.is_pastor() or ministry_id = public.my_ministry_id());
create policy "events scoped delete" on public.events for delete
using (public.is_pastor() or ministry_id = public.my_ministry_id());

-- Notícias: público vê apenas publicadas; líder só gerencia as do próprio ministério.
create policy "news public published read" on public.news for select
using (published = true or public.is_pastor() or ministry_id = public.my_ministry_id());
create policy "news scoped insert" on public.news for insert
with check (
  public.is_pastor()
  or (ministry_id = public.my_ministry_id() and created_by = auth.uid())
);
create policy "news scoped update" on public.news for update
using (public.is_pastor() or ministry_id = public.my_ministry_id())
with check (public.is_pastor() or ministry_id = public.my_ministry_id());
create policy "news scoped delete" on public.news for delete
using (public.is_pastor() or ministry_id = public.my_ministry_id());

-- Mídia: mesma regra de escopo por ministério.
create policy "media public read" on public.media_items for select using (true);
create policy "media scoped insert" on public.media_items for insert
with check (
  public.is_pastor()
  or (ministry_id = public.my_ministry_id() and created_by = auth.uid())
);
create policy "media scoped update" on public.media_items for update
using (public.is_pastor() or ministry_id = public.my_ministry_id())
with check (public.is_pastor() or ministry_id = public.my_ministry_id());
create policy "media scoped delete" on public.media_items for delete
using (public.is_pastor() or ministry_id = public.my_ministry_id());

grant usage on schema public to anon, authenticated;
grant select on public.ministries, public.events, public.media_items to anon, authenticated;
grant select, insert, update, delete on public.events, public.news, public.media_items to authenticated;
grant select on public.news to anon;
grant select, update on public.profiles to authenticated;
grant select on public.profiles to anon;
grant select on public.ministries to authenticated, anon;

-- IMPORTANTE: crie usuários pelo painel Authentication do Supabase.
-- Depois, um pastor deve atribuir role/ministry_id em public.profiles.
-- Nunca exponha a service_role key no navegador.
