// Gesta · funzione "news": legge le fonti della Taverna (siti e canali YouTube) e salva titoli, immagini e link.
// La chiama l'app di un tester quando apre la Taverna; ogni fonte si rilegge al massimo ogni 3 ore.
// Non servono segreti: SUPABASE_URL e SUPABASE_SERVICE_ROLE_KEY li mette Supabase da solo.
import { createClient } from "npm:@supabase/supabase-js@2.45.4";

const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
const CORS = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type", "Access-Control-Allow-Methods": "POST, OPTIONS" };
const UA = "Mozilla/5.0 (compatible; GestaOggi/1.0; +https://getgesta.app)";
const json = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { ...CORS, "Content-Type": "application/json" } });

// YouTube in Europa rimanda alla pagina dei cookie: con questo cookie la salta. E le ricerche vanno una alla volta, sennò YouTube blocca
const YT_COOKIE = "SOCS=CAI; CONSENT=YES+cb";
let ytLock: Promise<unknown> = Promise.resolve();
function ytGet(url: string) { const p = ytLock.then(() => new Promise((r) => setTimeout(r, 1500))).then(() => get(url)); ytLock = p.catch(() => {}); return p; }
// i redirect si seguono a mano tenendo i cookie: YouTube a volte rimbalza tra pagine finché non li riceve indietro
async function get(url: string, ms = 12000) {
  const jar: Record<string, string> = {};
  if (/youtube\.com/.test(url)) for (const c of YT_COOKIE.split("; ")) { const [k, v] = c.split("="); jar[k] = v; }
  let u = url;
  for (let i = 0; i < 8; i++) {
    const cookie = Object.entries(jar).map(([k, v]) => k + "=" + v).join("; ");
    const r = await fetch(u, { headers: { ...(cookie ? { "Cookie": cookie } : {}), "User-Agent": UA, "Accept": "application/rss+xml, application/atom+xml, application/xml, text/xml, text/html;q=0.8, */*;q=0.5", "Accept-Language": "it-IT,it;q=0.9,en;q=0.6" }, redirect: "manual", signal: AbortSignal.timeout(ms) });
    for (const sc of r.headers.getSetCookie?.() || []) { const m = sc.match(/^([^=;\s]+)=([^;]*)/); if (m) jar[m[1]] = m[2]; }
    const loc = r.headers.get("location");
    if (r.status >= 300 && r.status < 400 && loc) { await r.body?.cancel(); u = new URL(loc, u).href; continue; }
    if (!r.ok) throw new Error("HTTP " + r.status);
    return { text: await r.text(), url: u };
  }
  throw new Error("troppi rimbalzi");
}
const isFeed = (t: string) => /<(rss|feed|rdf:RDF)[\s>]/i.test(t.slice(0, 3000));

// trova il feed: canali YouTube, siti con <link rel="alternate">, oppure /feed/ di WordPress
async function discover(url: string): Promise<string> {
  if (url.startsWith("yt:")) {
    const q = url.slice(3).trim();
    // prima la ricerca per nome; se YouTube non risponde, la pagina @nomecanale
    const r1 = await ytGet("https://www.youtube.com/results?search_query=" + encodeURIComponent(q) + "&sp=EgIQAg%253D%253D").catch(() => null);
    const m = r1 && (r1.text.match(/"channelRenderer":\{"channelId":"(UC[\w-]{22})"/) || r1.text.match(/"channelId":"(UC[\w-]{22})"/));
    if (m) return "https://www.youtube.com/feeds/videos.xml?channel_id=" + m[1];
    return discover("https://www.youtube.com/@" + q.replace(/[^\w.-]/g, ""));
  }
  // il link di un video (anche uno Short): si risale al suo canale
  if (/youtube\.com\/(watch|shorts\/)|youtu\.be\//.test(url)) {
    const { text } = await ytGet(url);
    const m = text.match(/"channelId":"(UC[\w-]{22})"/) || text.match(/itemprop="channelId" content="(UC[\w-]{22})"/);
    if (!m) throw new Error("canale non trovato");
    return "https://www.youtube.com/feeds/videos.xml?channel_id=" + m[1];
  }
  if (/youtube\.com\/(@|channel\/|c\/|user\/)/.test(url)) {
    const m0 = url.match(/channel\/(UC[\w-]{22})/); if (m0) return "https://www.youtube.com/feeds/videos.xml?channel_id=" + m0[1];
    const { text } = await ytGet(url);
    const m = text.match(/"(?:channelId|externalId)":"(UC[\w-]{22})"/) || text.match(/channel_id=(UC[\w-]{22})/) || text.match(/itemprop="(?:channelId|identifier)" content="(UC[\w-]{22})"/);
    if (!m) throw new Error("canale non trovato");
    return "https://www.youtube.com/feeds/videos.xml?channel_id=" + m[1];
  }
  const home = await get(url).catch((e) => e as Error);
  if (home instanceof Error) {
    const t = await get(url.replace(/\/+$/, "") + "/feed/", 20000).catch(() => null);
    if (t && isFeed(t.text)) return t.url;
    throw home;
  }
  const { text, url: fin } = home;
  if (isFeed(text)) return fin;
  const links = [...text.matchAll(/<link\b[^>]*>/gi)].map((x) => x[0]).filter((l) => /rel=["']?alternate/i.test(l) && /type=["']?application\/(rss|atom)\+xml/i.test(l));
  for (const l of links) { const h = l.match(/href=["']([^"']+)["']/i); if (h && !/comments/i.test(h[1])) return new URL(h[1], fin).href; }
  const wp = fin.replace(/\/+$/, "") + "/feed/";
  const t2 = await get(wp).catch(() => null);
  if (t2 && isFeed(t2.text)) return t2.url;
  throw new Error("feed non trovato");
}

const ENT: Record<string, string> = { amp: "&", lt: "<", gt: ">", quot: '"', apos: "'", nbsp: " ", rsquo: "’", lsquo: "‘", rdquo: "”", ldquo: "“", hellip: "…", ndash: "–", mdash: "—", egrave: "è", eacute: "é", agrave: "à", ograve: "ò", ugrave: "ù", igrave: "ì" };
function dec(s: string) {
  return s.replace(/<!\[CDATA\[([\s\S]*?)\]\]>/g, "$1").replace(/&#(\d+);/g, (_, n) => String.fromCodePoint(+n)).replace(/&#x([0-9a-f]+);/gi, (_, n) => String.fromCodePoint(parseInt(n, 16))).replace(/&([a-z]+);/gi, (m, n) => ENT[n.toLowerCase()] ?? m);
}
function tag(b: string, names: string[]) {
  for (const n of names) { const m = b.match(new RegExp("<" + n + "(?:\\s[^>]*)?>([\\s\\S]*?)</" + n + ">", "i")); if (m && m[1].trim()) return dec(m[1]).replace(/<[^>]+>/g, "").trim(); }
  return "";
}
function attr(b: string, re: RegExp) { const m = b.match(re); return m ? dec(m[1]) : ""; }

export type Item = { title: string; link: string; image: string; date: string; views: number | null };
export function parse(xml: string): Item[] {
  const blocks = [...xml.matchAll(/<item[\s>][\s\S]*?<\/item>/gi)].map((x) => x[0]);
  const atom = !blocks.length;
  if (atom) for (const x of xml.matchAll(/<entry[\s>][\s\S]*?<\/entry>/gi)) blocks.push(x[0]);
  return blocks.map((b) => {
    const title = tag(b, ["title"]);
    let link = atom ? (attr(b, /<link\b[^>]*rel=["']alternate["'][^>]*href=["']([^"']+)["']/i) || attr(b, /<link\b[^>]*href=["']([^"']+)["']/i)) : (tag(b, ["link"]) || attr(b, /<guid[^>]*>(https?:[^<]+)<\/guid>/i));
    link = link.trim().replace(/^https?:\/\/(?:www\.)?youtube\.com\/shorts\/([\w-]{11}).*$/, "https://www.youtube.com/watch?v=$1#short");
    const date = tag(b, ["pubDate", "published", "updated", "dc:date"]);
    let image = attr(b, /<media:thumbnail\b[^>]*url=["']([^"']+)["']/i) || attr(b, /<media:content\b[^>]*url=["']([^"']+\.(?:jpe?g|png|webp)[^"']*)["']/i) ||
      attr(b, /<enclosure\b[^>]*url=["']([^"']+)["'][^>]*type=["']image/i) || attr(b, /<enclosure\b[^>]*type=["']image[^"']*["'][^>]*url=["']([^"']+)["']/i);
    if (!image) { const body = dec(b.match(/<(content:encoded|description|content|summary)[^>]*>([\s\S]*?)<\/\1>/i)?.[2] || ""); image = attr(body, /<img\b[^>]*src=["']([^"']+)["']/i); }
    const v = attr(b, /<media:statistics\b[^>]*views=["'](\d+)["']/i);
    return { title, link, image, date, views: v ? +v : null };
  }).filter((x) => x.title && /^https?:\/\//.test(x.link));
}

const TOP = /highlight|best of|best moments|finale?|final[s]?\b|semifinal|recap|sintesi|gold medal|medaglia/i;

async function readSource(s: any) {
  let feed = s.feed as string | null;
  if (!feed) feed = await discover(s.url);
  const { text } = await get(feed, 20000);
  const head = text.replace(/<(item|entry)[\s>][\s\S]*$/i, "");
  const title = tag(head, ["title"]).slice(0, 120);
  let items = parse(text);
  if (s.kind === "top") items = items.filter((x) => !/#short$/.test(x.link));
  if (s.kind === "top") { const hi = items.filter((x) => TOP.test(x.title)); items = [...hi, ...items.filter((x) => !TOP.test(x.title))].slice(0, 4); }
  else items = items.slice(0, s.kind === "video" ? 15 : 8);
  const rows = items.map((x) => {
    const d = Date.parse(x.date);
    return { source_id: s.id, sport: s.sport, kind: s.kind, title: x.title.slice(0, 300), link: x.link.replace(/#short$/, "").slice(0, 1000), image: x.image ? x.image.slice(0, 1000) : null, published_at: new Date(isNaN(d) ? Date.now() : Math.min(d, Date.now())).toISOString(), views: x.views };
  });
  if (rows.length) { const { error } = await sb.from("news_items").upsert(rows, { onConflict: "source_id,link" }); if (error) throw new Error(error.message); }
  return { feed, n: rows.length, title };
}

// i video più visti di ogni canale di tecnica, una volta a settimana, con la chiave YouTube (segreto YT_KEY). Shorts compresi
const YT_KEY = Deno.env.get("YT_KEY") || "";
async function ytApi(path: string) {
  const r = await fetch("https://www.googleapis.com/youtube/v3/" + path + "&key=" + YT_KEY, { signal: AbortSignal.timeout(15000) });
  const j = await r.json().catch(() => ({}));
  if (!r.ok || j.error) throw new Error("YouTube: " + ((j.error && j.error.message) || r.status));
  return j;
}
async function readPopular(s: any) {
  const ch = String(s.feed || "").match(/channel_id=(UC[\w-]{22})/);
  if (!ch) throw new Error("canale senza id");
  const sr = await ytApi("search?part=id&type=video&order=viewCount&maxResults=50&channelId=" + ch[1]);
  const ids = (sr.items || []).map((x: any) => x.id && x.id.videoId).filter(Boolean);
  if (!ids.length) return 0;
  const vr = await ytApi("videos?part=snippet,statistics&maxResults=50&id=" + ids.join(","));
  const rows = (vr.items || []).map((v: any) => {
    const t = v.snippet.thumbnails || {}, im = t.high || t.medium || t.default;
    return { source_id: s.id, sport: s.sport, kind: s.kind, title: String(v.snippet.title).slice(0, 300), link: "https://www.youtube.com/watch?v=" + v.id, image: im ? im.url : null, published_at: v.snippet.publishedAt, views: +((v.statistics && v.statistics.viewCount) || 0) };
  }).sort((a: any, b: any) => b.views - a.views).map((x: any, i: number) => ({ ...x, pop: i + 1 }));
  await sb.from("news_items").update({ pop: null }).eq("source_id", s.id);
  await sb.from("news_items").delete().eq("source_id", s.id).in("link", ids.map((id: string) => "https://www.youtube.com/shorts/" + id));
  const { error } = await sb.from("news_items").upsert(rows, { onConflict: "source_id,link" });
  if (error) throw new Error(error.message);
  return rows.length;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  const tok = (req.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "");
  const { data: u } = await sb.auth.getUser(tok);
  if (!u?.user) return json({ error: "entra con l'email" }, 401);
  const { data: t } = await sb.from("news_testers").select("user_id").eq("user_id", u.user.id).maybeSingle();
  if (!t) return json({ error: "non sei tra i tester" }, 403);
  const body = await req.json().catch(() => ({}));
  // 4.11: controllo di un link che un utente vuole aggiungere come fonte sua: si trova il feed, senza salvare niente
  if (body.check) {
    let url = String(body.check).trim();
    if (!/^https?:\/\//i.test(url)) url = "https://" + url;
    try {
      const feed = await discover(url);
      const { text } = await get(feed, 20000);
      const items = parse(text);
      const title = tag(text.replace(/<(item|entry)[\s>][\s\S]*$/i, ""), ["title"]).slice(0, 80);
      if (!items.length) return json({ ok: false, error: "Ho trovato la fonte, ma è vuota" });
      return json({ ok: true, url, feed, title: title || url, kind: /youtube\.com\/feeds/.test(feed) ? "video" : "news", n: items.length });
    } catch (e) {
      return json({ ok: false, error: /canale non trovato/.test(String((e as Error).message)) ? "Non trovo il canale: prova con il link della pagina del canale" : "Non trovo niente da leggere a questo link" });
    }
  }
  const { data: srcs } = await sb.from("news_sources").select("*").eq("active", true);
  const now = Date.now();
  const due = (srcs || []).filter((s: any) => body.force || !s.checked_at || now - Date.parse(s.checked_at) > 3 * 3600e3);
  const one = async (s: any) => {
    try {
      const r = await readSource(s);
      await sb.from("news_sources").update({ feed: r.feed, title: r.title, checked_at: new Date().toISOString(), ok: true, n: r.n, err: null }).eq("id", s.id);
    } catch (e) {
      await sb.from("news_sources").update({ checked_at: new Date().toISOString(), ok: false, err: String((e as Error).message || e).slice(0, 200), feed: /404|feed non trovato/.test(String((e as Error).message)) ? null : s.feed }).eq("id", s.id);
    }
  };
  const queue = due.slice(), res: unknown[] = [];
  await Promise.all(Array.from({ length: 8 }, async () => { while (queue.length) { const s = queue.shift(); await one(s); res.push(1); } }));
  // i più visti: al massimo 12 canali per volta, ognuno una volta a settimana (resta dentro la quota gratuita di YouTube)
  let pop = 0;
  if (YT_KEY) {
    const { data: fresh } = await sb.from("news_sources").select("*").eq("active", true).eq("kind", "video").eq("ok", true);
    const pdue = (fresh || []).filter((s: any) => /channel_id=/.test(s.feed || "") && (!s.pop_at || now - Date.parse(s.pop_at) > 7 * 864e5)).slice(0, 12);
    for (const s of pdue) {
      try { const n = await readPopular(s); await sb.from("news_sources").update({ pop_at: new Date().toISOString(), pop_n: n, pop_err: null }).eq("id", s.id); pop++; }
      catch (e) { const m = String((e as Error).message || e).slice(0, 200); await sb.from("news_sources").update({ pop_at: /quota/i.test(m) ? null : new Date().toISOString(), pop_err: m }).eq("id", s.id); if (/quota/i.test(m)) break; }
    }
  }
  // si tolgono le notizie lette più di 60 giorni fa; i più visti restano finché sono tra i più visti
  await sb.from("news_items").delete().lt("created_at", new Date(now - 60 * 864e5).toISOString()).is("pop", null);
  return json({ ok: true, letti: res.length, piuvisti: pop, chiave: !!YT_KEY });
});
