-- Gesta 4.22 · errori dai telefoni e regole più strette. Si può rilanciare.

-- 1. errori dell'app (senza dati personali), letti solo da chi fa Gesta
create table if not exists public.app_errors (
  id bigserial primary key,
  created_at timestamptz not null default now(),
  user_id uuid default auth.uid(),
  ver text check (char_length(ver) <= 20),
  screen text check (char_length(screen) <= 40),
  msg text not null check (char_length(msg) <= 500),
  src text check (char_length(src) <= 300),
  stack text check (char_length(stack) <= 2000),
  ua text check (char_length(ua) <= 200),
  n int not null default 1
);
create index if not exists app_errors_at on public.app_errors (created_at desc);
alter table public.app_errors enable row level security;
drop policy if exists p_err_insert on public.app_errors;
create policy p_err_insert on public.app_errors for insert to anon, authenticated with check (user_id is null or user_id = auth.uid());
drop policy if exists p_err_read on public.app_errors;
create policy p_err_read on public.app_errors for select to authenticated using (public.is_gesta_admin());
revoke all on public.app_errors from anon, authenticated;
grant insert (ver, screen, msg, src, stack, ua, n) on public.app_errors to anon, authenticated;
grant select on public.app_errors to authenticated;
grant usage on sequence public.app_errors_id_seq to anon, authenticated;
-- freni: 20 l'ora a testa, 300 l'ora in tutto; si tengono 60 giorni
create or replace function public.app_errors_guard() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if (select count(*) from app_errors where created_at > now() - interval '1 hour') >= 300 then return null; end if;
  if new.user_id is not null and (select count(*) from app_errors where user_id = new.user_id and created_at > now() - interval '1 hour') >= 20 then return null; end if;
  delete from app_errors where created_at < now() - interval '60 days';
  return new;
end $$;
drop trigger if exists app_errors_guard on public.app_errors;
create trigger app_errors_guard before insert on public.app_errors for each row execute function public.app_errors_guard();

-- 2. guanti: chi lo riceve risponde (accetta, rifiuta, propone, chiude) ma non può riscrivere la sfida
create or replace function public.challenge_guard() returns trigger language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid();
begin
  if me is null then return new; end if;
  if new.from_id is distinct from old.from_id or new.to_id is distinct from old.to_id or new.gang_id is distinct from old.gang_id then
    raise exception 'Non si può cambiare chi c''è nella sfida'; end if;
  if old.to_id is not null and me = old.to_id and me is distinct from old.from_id then
    if new.quest is distinct from old.quest or new.sport is distinct from old.sport or new.day is distinct from old.day
       or new.shared is distinct from old.shared or new.msg is distinct from old.msg or new.from_done is distinct from old.from_done then
      raise exception 'La sfida la può cambiare solo chi l''ha lanciata'; end if;
    if new.status in ('pending', 'withdrawn') and new.status is distinct from old.status then raise exception 'Stato non permesso'; end if;
  end if;
  return new;
end $$;
drop trigger if exists challenge_guard on public.challenges;
create trigger challenge_guard before update on public.challenges for each row execute function public.challenge_guard();

-- 3. funzioni: chi non è entrato non le chiama; quelle dei trigger non le chiama nessuno
revoke execute on function public.accept_friend(uuid) from anon, public;
revoke execute on function public.decline_friend(uuid) from anon, public;
revoke execute on function public.accept_invite(uuid) from anon, public;
revoke execute on function public.friend_inbox() from anon, public;
revoke execute on function public.friend_outbox() from anon, public;
revoke execute on function public.join_gang(text) from anon, public;
revoke execute on function public.profile_by_code(text) from anon, public;
revoke execute on function public.send_friend_request(text) from anon, public;
grant execute on function public.accept_friend(uuid), public.decline_friend(uuid), public.accept_invite(uuid), public.friend_inbox(), public.friend_outbox(), public.join_gang(text), public.profile_by_code(text), public.send_friend_request(text) to authenticated;
revoke execute on function public.handle_new_user() from anon, authenticated, public;
revoke execute on function public.news_share_guard() from anon, authenticated, public;
revoke execute on function public.app_errors_guard() from anon, authenticated, public;
revoke execute on function public.challenge_guard() from anon, authenticated, public;
alter function public.is_news_tester() set search_path = public;
