-- Gesta 4.9 · "Manda a un amico": i contenuti della Taverna mandati tra amici
-- Niente da cambiare: incolla tutto e premi Run. Si può rilanciare.

-- una riga per ogni invio: chi, a chi, e una copia del contenuto (così resta anche quando la Taverna lo toglie)
create table if not exists public.news_shares (
  id uuid primary key default gen_random_uuid(),
  from_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  to_id uuid not null references auth.users (id) on delete cascade,
  sport text not null,
  kind text not null,
  title text not null check (char_length(title) <= 300),
  link text not null check (char_length(link) <= 1000),
  image text check (char_length(image) <= 1000),
  src text check (char_length(src) <= 120),
  note text check (char_length(note) <= 60),
  created_at timestamptz not null default now(),
  opened_at timestamptz
);
create index if not exists news_shares_to on public.news_shares (to_id, created_at desc);
create index if not exists news_shares_from on public.news_shares (from_id, created_at desc);

alter table public.news_shares enable row level security;
-- si manda solo ai propri amici, a nome proprio
drop policy if exists p_share_insert on public.news_shares;
create policy p_share_insert on public.news_shares for insert to authenticated
  with check (from_id = auth.uid() and to_id <> auth.uid() and public.is_friend(from_id, to_id));
-- li vede solo chi li ha mandati e chi li ha ricevuti
drop policy if exists p_share_select on public.news_shares;
create policy p_share_select on public.news_shares for select to authenticated
  using (from_id = auth.uid() or to_id = auth.uid());
-- chi li riceve può solo segnarli come aperti
drop policy if exists p_share_update on public.news_shares;
create policy p_share_update on public.news_shares for update to authenticated
  using (to_id = auth.uid()) with check (to_id = auth.uid());
revoke update on public.news_shares from authenticated, anon;
grant select, insert on public.news_shares to authenticated;
grant update (opened_at) on public.news_shares to authenticated;

-- al massimo 40 invii al giorno a testa, e si tolgono da soli dopo 30 giorni
create or replace function public.news_share_guard() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if (select count(*) from public.news_shares where from_id = new.from_id and created_at > now() - interval '1 day') >= 40 then
    raise exception 'Troppi invii oggi: riprova domani';
  end if;
  delete from public.news_shares where created_at < now() - interval '30 days';
  return new;
end $$;
drop trigger if exists news_share_guard on public.news_shares;
create trigger news_share_guard before insert on public.news_shares for each row execute function public.news_share_guard();
