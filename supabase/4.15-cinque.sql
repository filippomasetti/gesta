-- Gesta 4.15 · il nuovo Cinque: uno per giornata (non più uno a settimana) e con il suo tipo (d'oro, di fuoco, fulmine…)
-- Niente da cambiare: incolla tutto e premi Run. Si può rilanciare.

alter table public.fives add column if not exists day date;
alter table public.fives add column if not exists sport text;
alter table public.fives add column if not exists kind text check (char_length(kind) <= 12);
-- i cinque vecchi, dati per la settimana, prendono come giorno il lunedì
update public.fives set day = week where day is null;
alter table public.fives alter column day set not null;
-- uno per amico per giornata
alter table public.fives drop constraint if exists fives_pkey;
alter table public.fives add primary key (from_id, to_id, day);
