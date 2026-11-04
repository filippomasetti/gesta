-- Gesta 4.6.1 · le fonti di Oggi si aggiornano dall'app
-- Da qui in poi l'elenco delle fonti lo tiene l'app: quando la apri tu (l'account in gesta_admins),
-- aggiunge le fonti nuove e spegne quelle tolte. Niente da cambiare: incolla tutto e premi Run.
drop policy if exists p_ns_admin_ins on public.news_sources;
create policy p_ns_admin_ins on public.news_sources for insert to authenticated
  with check (exists (select 1 from public.gesta_admins where user_id = auth.uid()));
drop policy if exists p_ns_admin_upd on public.news_sources;
create policy p_ns_admin_upd on public.news_sources for update to authenticated
  using (exists (select 1 from public.gesta_admins where user_id = auth.uid()))
  with check (exists (select 1 from public.gesta_admins where user_id = auth.uid()));
