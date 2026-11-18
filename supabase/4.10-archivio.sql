-- Gesta 4.10 · archivio dei video di tecnica per visualizzazioni
-- Niente da cambiare: incolla tutto e premi Run. Si può rilanciare.

-- quante visualizzazioni ha un video e che posto ha tra i più visti del suo canale (1 = il più visto)
alter table public.news_items add column if not exists views bigint;
alter table public.news_items add column if not exists pop int;
-- quando abbiamo chiesto a YouTube i più visti di quel canale, quanti ne sono arrivati, ed eventuale errore
alter table public.news_sources add column if not exists pop_at timestamptz;
alter table public.news_sources add column if not exists pop_n int;
alter table public.news_sources add column if not exists pop_err text;

-- gli Shorts ora si salvano con l'indirizzo normale del video: tolgo le copie vecchie, tornano alla prossima lettura
delete from public.news_items where link like '%youtube.com/shorts/%';
-- si rileggono subito tutte le fonti
update public.news_sources set checked_at = null;
