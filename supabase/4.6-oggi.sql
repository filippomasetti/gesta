-- Gesta 4.6 · Oggi (prova): notizie, video e highlights dei tuoi sport
-- Per ora la vedono solo i tester. Prima di premere Run cambia le due email qui sotto
-- (righe con LA-TUA-EMAIL e EMAIL-DELLA-TUA-RAGAZZA): quelle con cui entrate in Gesta.

-- chi prova Oggi
create table if not exists public.news_testers (
  user_id uuid primary key references auth.users (id) on delete cascade
);
alter table public.news_testers enable row level security;
insert into public.news_testers (user_id)
select id from auth.users where lower(email) in (lower('LA-TUA-EMAIL'), lower('EMAIL-DELLA-TUA-RAGAZZA'))
on conflict do nothing;

create or replace function public.is_news_tester() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from news_testers where user_id = auth.uid());
$$;
revoke all on function public.is_news_tester() from public, anon;
grant execute on function public.is_news_tester() to authenticated;

-- le fonti: news = notizie di settore, video = canali di tecnica, top = highlights dei campioni
create table if not exists public.news_sources (
  id serial primary key,
  sport text not null,
  name text not null,
  kind text not null check (kind in ('news', 'video', 'top')),
  url text not null unique,
  feed text,
  active boolean not null default true,
  checked_at timestamptz,
  ok boolean,
  n int,
  err text
);
alter table public.news_sources enable row level security;
drop policy if exists p_ns_read on public.news_sources;
create policy p_ns_read on public.news_sources for select to authenticated using (public.is_news_tester());

-- le notizie lette (titolo, immagine e link: l'articolo resta sul sito della fonte)
create table if not exists public.news_items (
  id bigserial primary key,
  source_id int references public.news_sources (id) on delete cascade,
  sport text not null,
  kind text not null,
  title text not null,
  link text not null unique,
  image text,
  published_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);
create index if not exists news_items_pub on public.news_items (published_at desc);
alter table public.news_items enable row level security;
drop policy if exists p_ni_read on public.news_items;
create policy p_ni_read on public.news_items for select to authenticated using (public.is_news_tester());

-- le fonti di partenza: si possono spegnere (active = false) o aggiungere dalla tabella news_sources
insert into public.news_sources (sport, name, kind, url) values
  ('gym', 'Project inVictus', 'news', 'https://www.projectinvictus.it/'),
  ('gym', 'Project inVictus', 'video', 'https://www.youtube.com/@ProjectInVictus'),
  ('gym', 'Jeff Nippard', 'video', 'https://www.youtube.com/@JeffNippard'),
  ('bld', 'Planetmountain', 'news', 'https://www.planetmountain.com/it/'),
  ('bld', 'Up-Climbing', 'news', 'https://www.up-climbing.com/'),
  ('bld', 'Hooper’s Beta', 'video', 'https://www.youtube.com/@HoopersBeta'),
  ('bld', 'IFSC', 'top', 'https://www.youtube.com/@IFSCclimbing'),
  ('run', 'The Running Club', 'news', 'https://www.therunningclub.it/'),
  ('run', 'Correre', 'news', 'https://www.correre.it/'),
  ('run', 'World Athletics', 'top', 'https://www.youtube.com/@WorldAthletics'),
  ('bch', 'Volleynews · beach', 'news', 'https://www.volleynews.it/category/beach-volley/feed/'),
  ('bch', 'Volleyball World', 'top', 'https://www.youtube.com/@volleyballworld'),
  ('pad', 'Padel Magazine Italia', 'news', 'https://padelmagazine.it/'),
  ('pad', 'The Padel School', 'video', 'https://www.youtube.com/@ThePadelSchool'),
  ('pad', 'Premier Padel', 'top', 'https://www.youtube.com/@PremierPadel'),
  ('swm', 'Nuoto.com', 'news', 'https://www.nuoto.com/'),
  ('swm', 'Effortless Swimming', 'video', 'https://www.youtube.com/@EffortlessSwimming'),
  ('swm', 'World Aquatics', 'top', 'https://www.youtube.com/@WorldAquaticsOfficial')
on conflict (url) do nothing;
