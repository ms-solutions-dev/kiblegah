// Relay for the Kiblegah app: the Quran Foundation client secret stays here; the app only knows
// the host of this Worker (build setting `RELAY_HOST`, Info key `VermittlerAdresi`).
//
// Routes (GET only; anything else is 404/405/400):
//   GET /saglik                                   Health check
//   GET /qf/v1/mushaf/<1..604>[?surum=v1|v2]      Line layout of one mushaf page
//                                                 (Quran Foundation Content API, OAuth)
//
// Response JSON keys (`sayfa`, `satirlar`, `hata`, ...) are part of the wire contract with the app
// and must not be renamed.

export interface Env {
  /** Secrets (`wrangler secret put ...`), never in wrangler.toml. */
  QF_CLIENT_ID?: string;
  QF_CLIENT_SECRET?: string;
  /** Vars from wrangler.toml. */
  RATE_LIMIT_PER_MIN?: string;
  /** Optional overrides of the Quran Foundation endpoints (e.g. the pre-production environment). */
  QF_API?: string;
  QF_OAUTH?: string;
  /** Cloudflare rate limiting binding (wrangler.toml); without it only the per-instance limit applies. */
  RATE_LIMITER?: { limit(o: { key: string }): Promise<{ success: boolean }> };
}

/** External dependencies of the handler; replaced in tests. */
export interface Deps {
  fetch: typeof fetch;
  /** Cache API (caches.default); `null` = no caching. */
  cache: Pick<Cache, "match" | "put"> | null;
  /** For background work (cache.put); without it the handler awaits the work. */
  waitUntil?: (p: Promise<unknown>) => void;
  now?: () => number;
}

// Quran Foundation allows caching for at most one week. The app keeps a page for up to 7 days
// itself, so the relay caches for one day only.
const QF_TTL = 24 * 3600;
const QF_API = "https://apis.quran.foundation/content/api/v4";
const QF_OAUTH = "https://oauth2.quran.foundation/oauth2/token";
const UA = "Kiblegah-Relay/1.0";

const MUSHAF = /^\/qf\/v1\/mushaf\/(\d{1,3})$/;

export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    return handle(request, env, {
      fetch: globalThis.fetch.bind(globalThis),
      cache: (globalThis as unknown as { caches: { default: Cache } }).caches.default,
      waitUntil: (p) => ctx.waitUntil(p),
    });
  },
};

export async function handle(request: Request, env: Env, d: Deps): Promise<Response> {
  if (request.method !== "GET") return error(405, "GET only");
  const url = new URL(request.url);
  if (url.pathname === "/saglik") return json({ tamam: true }, 200, "no-store");

  const m = MUSHAF.exec(url.pathname);
  if (!m) return error(404, "unknown route");

  if (!(await withinLimit(request, env, d))) return error(429, "too many requests");

  try {
    return await mushaf(Number(m[1]), url, env, d);
  } catch {
    // No details to the client (upstream errors could contain headers or URLs).
    return error(502, "upstream did not respond");
  }
}

// ── Per-IP rate limit ────────────────────────────────────────────────
// The in-memory counter is per Worker instance (per data center, possibly several instances,
// cleared on restart). It slows down a single noisy client but is not a global cap. For a real cap
// use the rate limiting binding (wrangler.toml) or a WAF rule.
const counters = new Map<string, { start: number; n: number }>();

export function resetRateLimit(): void {
  counters.clear();
}

async function withinLimit(request: Request, env: Env, d: Deps): Promise<boolean> {
  const ip = request.headers.get("CF-Connecting-IP") ?? "local";
  if (env.RATE_LIMITER) {
    const { success } = await env.RATE_LIMITER.limit({ key: ip });
    if (!success) return false;
  }
  const limit = Number(env.RATE_LIMIT_PER_MIN ?? "120") || 120;
  const now = (d.now ?? Date.now)();
  const c = counters.get(ip);
  if (!c || now - c.start >= 60_000) {
    if (counters.size > 10_000) counters.clear(); // bound memory use
    counters.set(ip, { start: now, n: 1 });
    return true;
  }
  c.n += 1;
  return c.n <= limit;
}

// ── Quran Foundation ─────────────────────────────────────────────────
let token: { value: string; expires: number } | null = null;

export function forgetToken(): void {
  token = null;
}

/** OAuth2 client credentials; kept in instance memory until shortly before expiry. */
async function qfToken(env: Env, d: Deps): Promise<string> {
  const now = (d.now ?? Date.now)();
  if (token && token.expires > now + 60_000) return token.value;
  const r = await d.fetch(env.QF_OAUTH || QF_OAUTH, {
    method: "POST",
    headers: {
      Authorization: "Basic " + btoa(`${env.QF_CLIENT_ID}:${env.QF_CLIENT_SECRET}`),
      "Content-Type": "application/x-www-form-urlencoded",
      "User-Agent": UA,
    },
    body: "grant_type=client_credentials&scope=content",
  });
  if (!r.ok) throw new Error(`oauth ${r.status}`);
  const body = (await r.json()) as { access_token: string; expires_in?: number };
  token = { value: body.access_token, expires: now + (Number(body.expires_in) || 3600) * 1000 };
  return token.value;
}

/** One word (or verse-end marker) of an API page, with its V1 and V2 positions. */
interface ApiWord {
  s: number;
  a: number;
  w: number;
  page: number;
  line: number;
  code: string;
  end: boolean;
  page2: number | null;
  line2: number | null;
  code2: string;
}

/** Words and verse-end markers of one API page (`verses/by_page`), cached. */
async function apiPage(n: number, env: Env, d: Deps): Promise<ApiWord[]> {
  const key = new Request(`https://relay.internal/qf/page/${n}`);
  const res = await cached(key, QF_TTL, d, async () => {
    const q = new URLSearchParams({
      words: "true",
      word_fields: "line_v1,v1_page,position,code_v1,line_v2,v2_page,code_v2",
      per_page: "50",
    });
    const r = await d.fetch(`${env.QF_API || QF_API}/verses/by_page/${n}?${q}`, {
      headers: { "x-auth-token": await qfToken(env, d), "x-client-id": env.QF_CLIENT_ID!, "User-Agent": UA },
    });
    if (r.status === 401 || r.status === 403) forgetToken();
    if (!r.ok) throw new Error(`qf ${r.status}`);
    const body = (await r.json()) as {
      verses: { verse_key: string; words: Record<string, unknown>[] }[];
    };
    const words: ApiWord[] = [];
    for (const v of body.verses) {
      const [s, a] = v.verse_key.split(":").map(Number);
      for (const w of v.words) {
        const type = w.char_type_name;
        if ((type === "word" || type === "end") && w.line_v1 && w.v1_page) {
          words.push({
            s,
            a,
            w: w.position as number,
            page: w.v1_page as number,
            line: w.line_v1 as number,
            code: (w.code_v1 as string) || "",
            end: type === "end",
            page2: (w.v2_page as number) ?? null,
            line2: (w.line_v2 as number) ?? null,
            code2: (w.code_v2 as string) || "",
          });
        }
      }
    }
    return json(words, 200);
  });
  if (!res.ok) throw new Error(`qf page ${res.status}`);
  return (await res.json()) as ApiWord[];
}

const order = (k: { s: number; a: number; w: number }) => [k.s, k.a, k.w];
const compare = (x: ApiWord, y: ApiWord) => {
  const [a, b] = [order(x), order(y)];
  for (let i = 0; i < 3; i++) if (a[i] !== b[i]) return a[i] - b[i];
  return 0;
};
const id = (k: ApiWord) => `${k.s}:${k.a}:${k.w}`;

/**
 * Page `n` in the V1 or V2 layout, in the JSON shape the app expects.
 * Words can belong to a neighbouring API page in the other layout, so pages n-1..n+1 are read.
 */
export async function mushafPage(n: number, version: "v1" | "v2", env: Env, d: Deps) {
  const v2 = version === "v2";
  const words: ApiWord[] = [];
  for (const m of [n - 1, n, n + 1]) {
    if (m < 1 || m > 604) continue;
    for (const k of await apiPage(m, env, d)) {
      const page = v2 ? k.page2 : k.page;
      const line = v2 ? k.line2 : k.line;
      if (page === n && line) words.push({ ...k, line, code: v2 ? k.code2 : k.code });
    }
  }
  const lines = new Map<number, ApiWord[]>();
  for (const k of words) {
    if (!lines.has(k.line)) lines.set(k.line, []);
    lines.get(k.line)!.push(k);
  }
  return {
    sayfa: n,
    kaynak: "Quran Foundation – KFGQPC " + (version === "v1" ? "V1 (1405 H)" : "V2/V4 (1421 H)"),
    yazi: version,
    satirlar: [...lines.entries()]
      .sort(([a], [b]) => a - b)
      .map(([no, l]) => {
        const plain = l.filter((k) => !k.end);
        const first = plain.length ? plain.reduce((x, y) => (compare(y, x) < 0 ? y : x)) : l[0];
        const last = plain.length ? plain.reduce((x, y) => (compare(y, x) > 0 ? y : x)) : l[l.length - 1];
        return {
          no,
          ilk: id(first),
          son: id(last),
          kelimeler: [...l].sort(compare).map((k) => ({ k: id(k), c: k.code || "", son: Boolean(k.end) })),
        };
      }),
  };
}

async function mushaf(n: number, url: URL, env: Env, d: Deps): Promise<Response> {
  for (const k of url.searchParams.keys()) if (k !== "surum") return error(400, `parameter: ${k}`);
  const version = url.searchParams.get("surum") ?? "v1";
  if (version !== "v1" && version !== "v2") return error(400, "surum must be v1 or v2");
  if (n < 1 || n > 604) return error(400, "page must be 1..604");
  if (!env.QF_CLIENT_ID || !env.QF_CLIENT_SECRET) return error(503, "quran foundation not configured");
  const key = new Request(`https://relay.internal/qf/mushaf/${version}/${n}`);
  return cached(key, QF_TTL, d, async () => json(await mushafPage(n, version, env, d), 200));
}

// ── Helpers ──────────────────────────────────────────────────────────

/** From the Cache API or freshly produced; only 200 responses are stored (for `ttl` seconds). */
async function cached(key: Request, ttl: number, d: Deps, produce: () => Promise<Response>): Promise<Response> {
  const hit = d.cache ? await d.cache.match(key) : undefined;
  if (hit) return hit;
  const res = await produce();
  if (res.status !== 200 || !d.cache) return res;
  const body = await res.text();
  const headers = new Headers(res.headers);
  headers.set("Cache-Control", `public, max-age=${ttl}`);
  const put = d.cache.put(key, new Response(body, { status: res.status, headers }));
  if (d.waitUntil) d.waitUntil(put);
  else await put;
  return new Response(body, { status: res.status, headers });
}

function json(data: unknown, status: number, cacheControl?: string): Response {
  const h: Record<string, string> = { "Content-Type": "application/json; charset=utf-8" };
  if (cacheControl) h["Cache-Control"] = cacheControl;
  return new Response(JSON.stringify(data), { status, headers: h });
}

/** Error body `{ "hata": "<message>" }`; the key is part of the wire contract, the message is not. */
function error(status: number, message: string): Response {
  return json({ hata: message }, status, "no-store");
}
