-- Gesta 4.5 · i calendari passati degli amici
-- Solo i giorni allenati con lo sport (gli stessi puntini che gli amici vedono già) e i giorni di Hard Study/Work.
-- Niente da cambiare: incolla tutto e premi Run.
create or replace function public.friend_month(f uuid, ym text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare d jsonb;
begin
  if auth.uid() is null or not (f = auth.uid() or is_friend(f, auth.uid())) then raise exception 'non autorizzato'; end if;
  if ym !~ '^\d{4}-\d{2}$' then raise exception 'mese non valido'; end if;
  select data into d from user_state where user_id = f;
  if d is null then return jsonb_build_object('days', '[]'::jsonb, 'hw', '[]'::jsonb); end if;
  return jsonb_build_object(
    'days', (select coalesce(jsonb_agg(jsonb_build_array(substr(k.key, 9, 2)::int, sp) order by k.key), '[]'::jsonb)
      from jsonb_each(coalesce(d -> 'days', '{}'::jsonb)) k,
      lateral (select jsonb_agg(distinct s ->> 'sport') as sp from jsonb_array_elements(case when jsonb_typeof(k.value) = 'array' then k.value else '[]'::jsonb end) s) z
      where k.key like ym || '-%' and sp is not null),
    'hw', (select coalesce(jsonb_agg(substr(m.key, 9, 2)::int), '[]'::jsonb)
      from jsonb_each(case when jsonb_typeof(d -> 'marks') = 'object' then d -> 'marks' else '{}'::jsonb end) m
      where m.key like ym || '-%'));
end;
$$;
revoke all on function public.friend_month(uuid, text) from public, anon;
grant execute on function public.friend_month(uuid, text) to authenticated;
