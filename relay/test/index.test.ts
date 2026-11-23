// Tests the fetch handler without Cloudflare: fetch and cache are replaced, nothing goes to the network.
import { beforeEach, describe, expect, it } from "vitest";
import { type Deps, type Env, forgetToken, handle, resetRateLimit } from "../src/index";

const ENV: Env = { QF_CLIENT_ID: "client-id", QF_CLIENT_SECRET: "secret" };

/** Records every call and answers by URL. */
function fake(answer: (url: string, init?: RequestInit) => Response) {
  const calls: { url: string; init?: RequestInit }[] = [];
  const f = (async (input: RequestInfo | URL, init?: RequestInit) => {
    const url = typeof input === "string" ? input : input instanceof URL ? input.href : input.url;
    calls.push({ url, init });
    return answer(url, init);
  }) as typeof fetch;
  return { f, calls };
}

function memoryCache(): NonNullable<Deps["cache"]> {
  const m = new Map<string, Response>();
  return {
    async match(r: RequestInfo | URL) {
      const k = typeof r === "string" ? r : r instanceof URL ? r.href : r.url;
      return m.get(k)?.clone();
    },
    async put(r: RequestInfo | URL, res: Response) {
      const k = typeof r === "string" ? r : r instanceof URL ? r.href : r.url;
      m.set(k, res.clone());
    },
  } as NonNullable<Deps["cache"]>;
}

const req = (path: string, init?: RequestInit) => new Request(`https://relay.example.com${path}`, init);

beforeEach(() => {
  resetRateLimit();
  forgetToken();
});

describe("routes", () => {
  it("GET only", async () => {
    const { f } = fake(() => new Response("{}"));
    const res = await handle(req("/saglik", { method: "POST" }), ENV, { fetch: f, cache: null });
    expect(res.status).toBe(405);
  });

  it("rejects unknown routes without touching the network", async () => {
    const { f, calls } = fake(() => new Response("{}"));
    for (const path of ["/", "/other/v1/route?x=1", "/qf/verses/by_page/1", "/qf/v1/mushaf/abc"]) {
      expect((await handle(req(path), ENV, { fetch: f, cache: null })).status).toBe(404);
    }
    expect(calls).toHaveLength(0);
  });

  it("health", async () => {
    const { f } = fake(() => new Response("{}"));
    const res = await handle(req("/saglik"), {}, { fetch: f, cache: null });
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ tamam: true });
  });
});

describe("rate limit", () => {
  it("per IP and minute", async () => {
    const { f } = fake(() => new Response("{}"));
    let t = 0;
    const d = { fetch: f, cache: null, now: () => t };
    const env = { ...ENV, RATE_LIMIT_PER_MIN: "2" };
    const ip = (x: string) => req("/qf/v1/mushaf/0", { headers: { "CF-Connecting-IP": x } });
    expect((await handle(ip("1.1.1.1"), env, d)).status).toBe(400);
    expect((await handle(ip("1.1.1.1"), env, d)).status).toBe(400);
    expect((await handle(ip("1.1.1.1"), env, d)).status).toBe(429);
    expect((await handle(ip("2.2.2.2"), env, d)).status).toBe(400);
    t = 61_000;
    expect((await handle(ip("1.1.1.1"), env, d)).status).toBe(400);
  });

  it("uses the Cloudflare binding when present", async () => {
    const { f } = fake(() => new Response("{}"));
    const env: Env = { ...ENV, RATE_LIMITER: { limit: async () => ({ success: false }) } };
    expect((await handle(req("/qf/v1/mushaf/1"), env, { fetch: f, cache: null })).status).toBe(429);
  });

  it("when the binding allows, the per-instance limit still applies", async () => {
    const { f } = fake(() => new Response("{}"));
    let asked = 0;
    const env: Env = {
      ...ENV,
      RATE_LIMIT_PER_MIN: "1",
      RATE_LIMITER: { limit: async () => (asked++, { success: true }) },
    };
    expect((await handle(req("/qf/v1/mushaf/0"), env, { fetch: f, cache: null })).status).toBe(400);
    expect((await handle(req("/qf/v1/mushaf/0"), env, { fetch: f, cache: null })).status).toBe(429);
    expect(asked).toBe(2);
  });
});

describe("Quran Foundation", () => {
  // Page 1: two lines; one verse-end marker; a word without a V1 line is dropped.
  const apiPage = (n: number) => ({
    verses:
      n === 1
        ? [
            {
              verse_key: "1:1",
              words: [
                { char_type_name: "word", position: 2, v1_page: 1, line_v1: 2, code_v1: "B", v2_page: 1, line_v2: 2, code_v2: "b" },
                { char_type_name: "word", position: 1, v1_page: 1, line_v1: 2, code_v1: "A", v2_page: 1, line_v2: 2, code_v2: "a" },
                { char_type_name: "end", position: 3, v1_page: 1, line_v1: 2, code_v1: "E", v2_page: 1, line_v2: 3, code_v2: "e" },
                { char_type_name: "pause", position: 4, v1_page: 1, line_v1: 2, code_v1: "P" },
                { char_type_name: "word", position: 5, v1_page: 1, code_v1: "X" },
              ],
            },
            {
              verse_key: "1:2",
              words: [{ char_type_name: "word", position: 1, v1_page: 1, line_v1: 3, code_v1: "C", v2_page: 1, line_v2: 3, code_v2: "c" }],
            },
          ]
        : [
            {
              verse_key: "2:1",
              words: [{ char_type_name: "word", position: 1, v1_page: 2, line_v1: 2, code_v1: "D", v2_page: 2, line_v2: 2 }],
            },
          ],
  });

  function qf() {
    return fake((url) => {
      if (url.startsWith("https://oauth2.quran.foundation/")) {
        return Response.json({ access_token: "token-1", expires_in: 3600 });
      }
      const m = /\/verses\/by_page\/(\d+)\?/.exec(url);
      if (m) return Response.json(apiPage(Number(m[1])));
      return new Response("", { status: 500 });
    });
  }

  it("returns the JSON shape the app expects", async () => {
    const { f } = qf();
    const res = await handle(req("/qf/v1/mushaf/1"), ENV, { fetch: f, cache: null });
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({
      sayfa: 1,
      kaynak: "Quran Foundation – KFGQPC V1 (1405 H)",
      yazi: "v1",
      satirlar: [
        {
          no: 2,
          ilk: "1:1:1",
          son: "1:1:2",
          kelimeler: [
            { k: "1:1:1", c: "A", son: false },
            { k: "1:1:2", c: "B", son: false },
            { k: "1:1:3", c: "E", son: true },
          ],
        },
        { no: 3, ilk: "1:2:1", son: "1:2:1", kelimeler: [{ k: "1:2:1", c: "C", son: false }] },
      ],
    });
  });

  it("V2 layout takes lines and glyph codes from v2", async () => {
    const { f } = qf();
    const body = (await (await handle(req("/qf/v1/mushaf/1?surum=v2"), ENV, { fetch: f, cache: null })).json()) as {
      yazi: string;
      kaynak: string;
      satirlar: { no: number; kelimeler: { c: string }[] }[];
    };
    expect(body.yazi).toBe("v2");
    expect(body.kaynak).toBe("Quran Foundation – KFGQPC V2/V4 (1421 H)");
    expect(body.satirlar.map((s) => [s.no, s.kelimeler.map((k) => k.c).join("")])).toEqual([
      [2, "ab"],
      [3, "ec"], // reading order: 1:1:3 (verse end) before 1:2:1
    ]);
  });

  it("fetches the token server-side with Basic auth and reuses it", async () => {
    const { f, calls } = qf();
    const d = { fetch: f, cache: null };
    await handle(req("/qf/v1/mushaf/1"), ENV, d);
    await handle(req("/qf/v1/mushaf/2"), ENV, d);
    const oauth = calls.filter((c) => c.url.startsWith("https://oauth2.quran.foundation/"));
    expect(oauth).toHaveLength(1);
    const h = new Headers(oauth[0].init?.headers);
    expect(h.get("Authorization")).toBe("Basic " + btoa("client-id:secret"));
    const api = calls.filter((c) => c.url.includes("/verses/by_page/"));
    expect(new Headers(api[0].init?.headers).get("x-auth-token")).toBe("token-1");
    expect(new Headers(api[0].init?.headers).get("x-client-id")).toBe("client-id");
  });

  it("serves neighbouring and finished pages from the cache", async () => {
    const { f, calls } = qf();
    const d = { fetch: f, cache: memoryCache() };
    await handle(req("/qf/v1/mushaf/2"), ENV, d); // fetches 1, 2, 3
    const again = await handle(req("/qf/v1/mushaf/2"), ENV, d); // finished page cached
    expect(again.headers.get("Cache-Control")).toBe("public, max-age=86400");
    await handle(req("/qf/v1/mushaf/3"), ENV, d); // fetches only 4
    const api = calls.filter((c) => c.url.includes("/verses/by_page/")).map((c) => /by_page\/(\d+)/.exec(c.url)![1]);
    expect(api).toEqual(["1", "2", "3", "4"]);
  });

  it("validates page and parameters", async () => {
    const { f, calls } = qf();
    const d = { fetch: f, cache: null };
    for (const path of ["/qf/v1/mushaf/0", "/qf/v1/mushaf/605", "/qf/v1/mushaf/1?surum=v4", "/qf/v1/mushaf/1?x=1"]) {
      expect((await handle(req(path), ENV, d)).status).toBe(400);
    }
    expect(calls).toHaveLength(0);
  });

  it("503 without credentials, 502 without upstream, no details leaked", async () => {
    const { f } = qf();
    expect((await handle(req("/qf/v1/mushaf/1"), {}, { fetch: f, cache: null })).status).toBe(503);
    const broken = fake(() => new Response("token=topsecret", { status: 500 }));
    const res = await handle(req("/qf/v1/mushaf/1"), ENV, { fetch: broken.f, cache: memoryCache() });
    expect(res.status).toBe(502);
    expect(await res.text()).not.toContain("topsecret");
  });
});
