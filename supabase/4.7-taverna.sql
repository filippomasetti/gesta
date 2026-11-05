-- Gesta 4.7 · Taverna: tutti gli sport, fonti per tipo (tecnica, highlights, notizie, notizie per chi pratica)
-- Niente da cambiare: incolla tutto e premi Run.

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
