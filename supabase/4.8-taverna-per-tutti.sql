-- Gesta 4.8 · la Taverna per tutti
-- Le notizie sono contenuti pubblici (titolo, immagine e link): le può leggere chiunque usi Gesta.
-- Niente da cambiare: incolla tutto e premi Run.


-- (ripete la 4.7, nel caso non fosse stata lanciata: rilanciarla non fa danni)

-- un tipo in più: "local" = notizie per chi pratica (gare aperte, eventi, condizioni)
alter table public.news_sources drop constraint if exists news_sources_kind_check;
alter table public.news_sources add constraint news_sources_kind_check check (kind in ('news', 'video', 'top', 'local'));
-- il nome vero del canale o del sito trovato, per controllare che sia quello giusto
alter table public.news_sources add column if not exists title text;

-- la stessa fonte può servire a due sport (es. Volleyball World per beach e pallavolo)
alter table public.news_sources drop constraint if exists news_sources_url_key;
create unique index if not exists news_sources_sport_url on public.news_sources (sport, url);
alter table public.news_items drop constraint if exists news_items_link_key;
create unique index if not exists news_items_sport_link on public.news_items (sport, link);

-- chi apre la Taverna può far rileggere le fonti: ora vale per ogni utente con l'email collegata
drop table if exists public.news_testers cascade;
create or replace view public.news_testers as select id as user_id from auth.users;
revoke all on public.news_testers from anon, authenticated;

create or replace function public.is_news_tester() returns boolean
language sql stable as $$ select true $$;

drop policy if exists p_ns_read on public.news_sources;
create policy p_ns_read on public.news_sources for select to anon, authenticated using (true);
drop policy if exists p_ni_read on public.news_items;
create policy p_ni_read on public.news_items for select to anon, authenticated using (true);
