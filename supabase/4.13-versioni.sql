-- Gesta 4.13 · quale versione dell'app usa chi apre Gesta (solo totali, in Gesta in numeri)
-- Niente da cambiare: incolla tutto e premi Run. Si può rilanciare.

alter table public.app_days add column if not exists ver text check (char_length(ver) <= 30);

-- per ogni utente attivo negli ultimi 30 giorni si guarda l'ultima apertura; vuoto = versione prima della 4.13
create or replace function public.gesta_versions() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not exists (select 1 from gesta_admins where user_id = auth.uid()) then raise exception 'Solo per chi fa Gesta'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('ver', v.ver, 'n', v.n, 'last', v.last) order by v.last desc)
    from (select coalesce(l.ver, '') as ver, count(*) as n, max(l.day) as last
          from (select distinct on (user_id) user_id, ver, day from app_days where day > current_date - 30 order by user_id, day desc) l
          group by 1) v), '[]'::jsonb);
end $$;
revoke all on function public.gesta_versions() from public, anon;
grant execute on function public.gesta_versions() to authenticated;
