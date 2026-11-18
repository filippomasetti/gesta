-- Gesta 4.12 · consumi della chiave YouTube, per la dashboard in Gesta in numeri
-- Niente da cambiare: incolla tutto e premi Run. Si può rilanciare.

-- ogni volta che la funzione news usa la chiave scrive qui quante unità ha speso (dall'app non si legge né si scrive)
create table if not exists public.yt_usage (
  id bigserial primary key,
  at timestamptz not null default now(),
  source_id int references public.news_sources (id) on delete set null,
  sport text,
  units int not null
);
create index if not exists yt_usage_at on public.yt_usage (at);
alter table public.yt_usage enable row level security;

-- solo per chi fa Gesta: oggi (giorno di Google, si azzera alle 9 italiane), ultimi 14 giorni, e per sport
create or replace function public.gesta_youtube() returns jsonb
language plpgsql security definer set search_path = public as $$
declare g0 timestamptz := (date_trunc('day', now() at time zone 'America/Los_Angeles')) at time zone 'America/Los_Angeles';
begin
  if not exists (select 1 from gesta_admins where user_id = auth.uid()) then raise exception 'Solo per chi fa Gesta'; end if;
  delete from yt_usage where at < now() - interval '90 days';
  return jsonb_build_object(
    'quota', 10000,
    'today', (select coalesce(sum(units), 0) from yt_usage where at >= g0),
    'week', (select coalesce(sum(units), 0) from yt_usage where at >= now() - interval '7 days'),
    'days', (select jsonb_agg(jsonb_build_object('d', d::date, 'u', coalesce(x.s, 0)) order by d)
             from generate_series((now() at time zone 'Europe/Rome')::date - 13, (now() at time zone 'Europe/Rome')::date, interval '1 day') d
             left join (select (at at time zone 'Europe/Rome')::date dd, sum(units) s from yt_usage group by 1) x on x.dd = d::date),
    'sports', (select coalesce(jsonb_agg(t order by t.est desc, t.sport), '[]'::jsonb) from (
               select ns.sport,
                 count(*) as srcs,
                 count(*) filter (where ns.owner is not null) as own,
                 count(*) * 101 as est,
                 (select coalesce(sum(units), 0) from yt_usage u where u.sport = ns.sport and u.at >= now() - interval '7 days') as u7,
                 (select count(*) from profiles p where p.summary -> 'sports' ? ns.sport) as users
               from news_sources ns where ns.active and ns.kind = 'video' group by ns.sport) t)
  );
end $$;
revoke all on function public.gesta_youtube() from public, anon;
grant execute on function public.gesta_youtube() to authenticated;
