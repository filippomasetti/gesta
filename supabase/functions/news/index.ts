// Gesta · funzione "news": legge le fonti di Oggi (siti e canali YouTube) e salva titoli, immagini e link.
// La chiama l'app di un tester quando apre Oggi; ogni fonte si rilegge al massimo ogni 3 ore.
// Non servono segreti: SUPABASE_URL e SUPABASE_SERVICE_ROLE_KEY li mette Supabase da solo.
import { createClient } from "npm:@supabase/supabase-js@2.45.4";

const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
const CORS = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type", "Access-Control-Allow-Methods": "POST, OPTIONS" };
const UA = "Mozilla/5.0 (compatible; GestaOggi/1.0; +https://getgesta.app)";
const json = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { ...CORS, "Content-Type": "application/json" } });

async function get(url: string) {
  const r = await fetch(url, { headers: { "User-Agent": UA, "Accept": "application/rss+xml, application/atom+xml, application/xml, text/xml, text/html;q=0.8, */*;q=0.5", "Accept-Language": "it-IT,it;q=0.9,en;q=0.6" }, redirect: "follow", signal: AbortSignal.timeout(10000) });
  if (!r.ok) throw new Error("HTTP " + r.status);
  return { text: await r.text(), url: r.url };
}
const isFeed = (t: string) => /<(rss|feed|rdf:RDF)[\s>]/i.test(t.slice(0, 3000));

// trova il feed: canali YouTube, siti con <link rel="alternate">, oppure /feed/ di WordPress
async function discover(url: string): Promise<string> {
  if (/youtube\.com\/(@|channel\/|c\/|user\/)/.test(url)) {
    const m0 = url.match(/channel\/(UC[\w-]{22})/); if (m0) return "https://www.youtube.com/feeds/videos.xml?channel_id=" + m0[1];
    const { text } = await get(url);
    const m = text.match(/"(?:channelId|externalId)":"(UC[\w-]{22})"/) || text.match(/channel_id=(UC[\w-]{22})/) || text.match(/itemprop="(?:channelId|identifier)" content="(UC[\w-]{22})"/);
    if (!m) throw new Error("canale non trovato");
    return "https://www.youtube.com/feeds/videos.xml?channel_id=" + m[1];
  }
  const { text, url: fin } = await get(url);
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

export type Item = { title: string; link: string; image: string; date: string };
export function parse(xml: string): Item[] {
  const blocks = [...xml.matchAll(/<item[\s>][\s\S]*?<\/item>/gi)].map((x) => x[0]);
  const atom = !blocks.length;
  if (atom) for (const x of xml.matchAll(/<entry[\s>][\s\S]*?<\/entry>/gi)) blocks.push(x[0]);
  return blocks.map((b) => {
    const title = tag(b, ["title"]);
    let link = atom ? (attr(b, /<link\b[^>]*rel=["']alternate["'][^>]*href=["']([^"']+)["']/i) || attr(b, /<link\b[^>]*href=["']([^"']+)["']/i)) : (tag(b, ["link"]) || attr(b, /<guid[^>]*>(https?:[^<]+)<\/guid>/i));
    link = link.trim();
    const date = tag(b, ["pubDate", "published", "updated", "dc:date"]);
    let image = attr(b, /<media:thumbnail\b[^>]*url=["']([^"']+)["']/i) || attr(b, /<media:content\b[^>]*url=["']([^"']+\.(?:jpe?g|png|webp)[^"']*)["']/i) ||
      attr(b, /<enclosure\b[^>]*url=["']([^"']+)["'][^>]*type=["']image/i) || attr(b, /<enclosure\b[^>]*type=["']image[^"']*["'][^>]*url=["']([^"']+)["']/i);
    if (!image) { const body = dec(b.match(/<(content:encoded|description|content|summary)[^>]*>([\s\S]*?)<\/\1>/i)?.[2] || ""); image = attr(body, /<img\b[^>]*src=["']([^"']+)["']/i); }
    return { title, link, image, date };
  }).filter((x) => x.title && /^https?:\/\//.test(x.link));
}

const TOP = /highlight|best of|best moments|finale?|final[s]?\b|semifinal|recap|sintesi|gold medal|medaglia/i;

async function readSource(s: any) {
  let feed = s.feed as string | null;
  if (!feed) feed = await discover(s.url);
  const { text } = await get(feed);
  let items = parse(text);
  if (s.kind === "top") items = items.filter((x) => TOP.test(x.title)).slice(0, 4); else items = items.slice(0, 8);
  const rows = items.map((x) => {
    const d = Date.parse(x.date);
    return { source_id: s.id, sport: s.sport, kind: s.kind, title: x.title.slice(0, 300), link: x.link.slice(0, 1000), image: x.image ? x.image.slice(0, 1000) : null, published_at: new Date(isNaN(d) ? Date.now() : Math.min(d, Date.now())).toISOString() };
  });
  if (rows.length) { const { error } = await sb.from("news_items").upsert(rows, { onConflict: "link", ignoreDuplicates: true }); if (error) throw new Error(error.message); }
  return { feed, n: rows.length };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  const tok = (req.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "");
  const { data: u } = await sb.auth.getUser(tok);
  if (!u?.user) return json({ error: "entra con l'email" }, 401);
  const { data: t } = await sb.from("news_testers").select("user_id").eq("user_id", u.user.id).maybeSingle();
  if (!t) return json({ error: "non sei tra i tester" }, 403);
  const body = await req.json().catch(() => ({}));
  const { data: srcs } = await sb.from("news_sources").select("*").eq("active", true);
  const now = Date.now();
  const due = (srcs || []).filter((s: any) => body.force || !s.checked_at || now - Date.parse(s.checked_at) > 3 * 3600e3);
  const res = await Promise.allSettled(due.map(async (s: any) => {
    try {
      const r = await readSource(s);
      await sb.from("news_sources").update({ feed: r.feed, checked_at: new Date().toISOString(), ok: true, n: r.n, err: null }).eq("id", s.id);
    } catch (e) {
      await sb.from("news_sources").update({ checked_at: new Date().toISOString(), ok: false, err: String((e as Error).message || e).slice(0, 200), feed: null }).eq("id", s.id);
    }
  }));
  await sb.from("news_items").delete().lt("published_at", new Date(now - 45 * 864e5).toISOString());
  return json({ ok: true, letti: res.length });
});
