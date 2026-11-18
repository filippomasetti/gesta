-- Gesta 4.11 · Taverna: le fonti tue (private o proposte a tutti) e l'approvazione in Gesta in numeri
-- Niente da cambiare: incolla tutto e premi Run. Si può rilanciare.

-- chi ha aggiunto la fonte (vuoto = fonte di Gesta) e se l'ha proposta: 'proposed', 'yes' (per tutti), 'no' (resta sua)
alter table public.news_sources add column if not exists owner uuid references auth.users (id) on delete cascade;
alter table public.news_sources add column if not exists shared text check (shared in ('proposed', 'yes', 'no'));
alter table public.news_sources add column if not exists created_at timestamptz not null default now();

-- la stessa fonte può essere di Gesta e, separatamente, tua
drop index if exists public.news_sources_sport_url;
create unique index if not exists news_sources_sport_url_owner on public.news_sources (sport, url, owner) nulls not distinct;
-- un contenuto è unico dentro la sua fonte
drop index if exists public.news_items_sport_link;
create unique index if not exists news_items_src_link on public.news_items (source_id, link);

-- chi vede cosa: le fonti di Gesta e quelle approvate tutti; le tue solo tu (e chi fa Gesta, per approvarle)
grant execute on function public.is_gesta_admin() to anon, authenticated;
drop policy if exists p_ns_read on public.news_sources;
create policy p_ns_read on public.news_sources for select to anon, authenticated
  using (owner is null or shared = 'yes' or owner = auth.uid() or public.is_gesta_admin());
drop policy if exists p_ni_read on public.news_items;
create policy p_ni_read on public.news_items for select to anon, authenticated
  using (exists (select 1 from public.news_sources s where s.id = news_items.source_id and (s.owner is null or s.shared = 'yes' or s.owner = auth.uid())));

-- aggiungere una fonte tua (al massimo 10)
create or replace function public.my_source_add(p_sport text, p_url text, p_kind text, p_name text, p_feed text, p_propose boolean)
returns int language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); nid int;
begin
  if me is null then raise exception 'Entra con l''email per aggiungere fonti'; end if;
  if p_sport !~ '^[a-z]{3}$' or p_kind not in ('video', 'news') or coalesce(p_url, '') = '' then raise exception 'Fonte non valida'; end if;
  if exists (select 1 from news_sources where sport = p_sport and active and (owner is null or shared = 'yes') and (url = p_url or (p_feed is not null and feed = p_feed))) then
    raise exception 'C''è già nella Taverna di questo sport'; end if;
  if exists (select 1 from news_sources where sport = p_sport and active and owner = me and (url = p_url or (p_feed is not null and feed = p_feed))) then
    raise exception 'L''hai già aggiunta'; end if;
  if (select count(*) from news_sources where owner = me and active) >= 10 then
    raise exception 'Hai già 10 fonti tue: togline una per aggiungerne un''altra'; end if;
  insert into news_sources (sport, name, kind, url, feed, active, owner, shared, checked_at)
  values (p_sport, left(coalesce(nullif(p_name, ''), p_url), 80), p_kind, left(p_url, 500), left(p_feed, 1000), true, me, case when p_propose then 'proposed' end, null)
  on conflict (sport, url, owner) do update set active = true, name = excluded.name, kind = excluded.kind, feed = excluded.feed, shared = excluded.shared, checked_at = null
  returning id into nid;
  return nid;
end $$;

-- toglierla: se era stata approvata resta per tutti gli altri, diventa di Gesta
create or replace function public.my_source_remove(p_id int) returns void
language plpgsql security definer set search_path = public as $$
begin
  update news_sources set owner = null where id = p_id and owner = auth.uid() and shared = 'yes';
  delete from news_sources where id = p_id and owner = auth.uid();
end $$;

-- solo per chi fa Gesta: le proposte e la decisione
create or replace function public.gesta_proposals() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not exists (select 1 from gesta_admins where user_id = auth.uid()) then raise exception 'Solo per chi fa Gesta'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', s.id, 'sport', s.sport, 'name', s.name, 'title', s.title, 'url', s.url, 'kind', s.kind,
    'ok', s.ok, 'n', s.n, 'err', s.err, 'who', coalesce(p.name, 'Qualcuno')) order by s.created_at)
    from news_sources s left join profiles p on p.id = s.owner where s.shared = 'proposed' and s.active), '[]'::jsonb);
end $$;
create or replace function public.source_decide(p_id int, p_ok boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from gesta_admins where user_id = auth.uid()) then raise exception 'Solo per chi fa Gesta'; end if;
  update news_sources set shared = case when p_ok then 'yes' else 'no' end where id = p_id and shared = 'proposed';
end $$;

revoke all on function public.my_source_add(text, text, text, text, text, boolean) from public, anon;
revoke all on function public.my_source_remove(int) from public, anon;
revoke all on function public.gesta_proposals() from public, anon;
revoke all on function public.source_decide(int, boolean) from public, anon;
grant execute on function public.my_source_add(text, text, text, text, text, boolean) to authenticated;
grant execute on function public.my_source_remove(int) to authenticated;
grant execute on function public.gesta_proposals() to authenticated;
grant execute on function public.source_decide(int, boolean) to authenticated;
