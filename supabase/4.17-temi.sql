-- Gesta 4.17 · temi nascosti: chi li ha sbloccati (per email). Si può rilanciare.
-- Per sbloccare un tema: insert into public.theme_unlocks (email, themes) values ('nome@esempio.it', '{rosa}')
--   on conflict (email) do update set themes = excluded.themes;
create table if not exists public.theme_unlocks (
  email text primary key check (email = lower(email)),
  themes text[] not null default '{}',
  created_at timestamptz not null default now()
);
alter table public.theme_unlocks enable row level security;
-- ognuno legge solo la propria riga; scrivere si può solo dalla dashboard
drop policy if exists p_tu_read on public.theme_unlocks;
create policy p_tu_read on public.theme_unlocks for select to authenticated
  using (email = lower(coalesce(auth.jwt() ->> 'email', '')));
revoke all on public.theme_unlocks from anon, authenticated;
grant select on public.theme_unlocks to authenticated;
