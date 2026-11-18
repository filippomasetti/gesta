-- Gesta 4.8.4 · quattro siti di notizie sostituiti (non rispondevano) e si riprovano le fonti che non andavano
-- Niente da cambiare: incolla tutto e premi Run. Si può rilanciare.
update public.news_sources set active = false where (sport, url) in (values
  ('cfx', 'https://morningchalkup.com/'),
  ('swm', 'https://www.nuoto.com/'),
  ('trk', 'https://loscarpone.cai.it/'),
  ('dnc', 'https://www.danzaedanzaweb.com/'));
insert into public.news_sources (sport, name, kind, url, active) values
  ('cfx', 'BoxRox', 'news', 'https://www.boxrox.com/', true),
  ('swm', 'Sportface · nuoto', 'news', 'https://www.sportface.it/nuoto/', true),
  ('trk', 'Mountainblog', 'news', 'https://www.mountainblog.it/', true),
  ('dnc', 'Dance Magazine', 'news', 'https://www.dancemagazine.com/', true)
on conflict (sport, url) do update set name = excluded.name, kind = excluded.kind, active = true;
-- chi non andava (o aveva pochi video di highlights) si rilegge da capo
update public.news_sources set checked_at = null, feed = case when ok is distinct from true then null else feed end
  where ok is distinct from true or n < 4;
