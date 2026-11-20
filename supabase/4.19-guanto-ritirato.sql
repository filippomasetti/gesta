-- Gesta 4.19 · chi lancia un guanto può ritirarlo: nuovo stato 'withdrawn'. Si può rilanciare.
alter table public.challenges drop constraint if exists challenges_status_check;
alter table public.challenges add constraint challenges_status_check check (status = any (array['pending','accepted','declined','countered','won','over','expired','open','passed','void','withdrawn']));
