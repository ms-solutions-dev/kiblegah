# Kiblegah relay (Cloudflare Worker)

A small public Worker between the Kiblegah iOS app and the Quran Foundation Content API.

The Quran Foundation API uses OAuth2 client credentials. A client secret shipped inside an app
binary is not a secret, so the app never holds it. Instead, this relay keeps the credentials,
exchanges them for an access token, and serves the line layout of mushaf pages to the app.

The relay is optional. Without it (no `RELAY_HOST` configured, or the relay unreachable) the app
still works and shows the Quran as a reflowed text view instead of the page-exact mushaf layout.

## Routes

| Route | Source | Cache |
|---|---|---|
| `GET /qf/v1/mushaf/<1..604>[?surum=v1\|v2]` | Quran Foundation Content API `verses/by_page` (OAuth), converted to the line layout the app expects | 1 day |
| `GET /saglik` | Health check, returns `{"tamam":true}` | none |

Anything else: 404 (unknown route), 400 (unknown parameter, invalid page or `surum`), 405 (not GET),
429 (rate limit), 503 (credentials not configured), 502 (upstream error, no details passed on).

`surum=v1` (default) is the KFGQPC V1 (1405 H) layout, `surum=v2` the V2/V4 (1421 H) layout.
The response shape (`sayfa`, `kaynak`, `yazi`, `satirlar[].no/ilk/son/kelimeler[].k/c/son`, and
`hata` for errors) is the contract with the app; do not rename its keys.

## Before you deploy: your own Quran Foundation credentials

You need your own API client from Quran Foundation (https://api-docs.quran.foundation). Do not
reuse anyone else's credentials. By using the API you accept its terms, in particular:

- **Caching at most one week.** The relay caches API pages and finished mushaf pages for one day.
  The app caches a page for up to 7 days on the device, so a page can be up to 8 days old in the
  worst case; lower the app-side lifetime if you need strict compliance.
- **Attribution.** Every response carries the source in `kaynak`; the app shows it.
- **Access is revocable.** Quran Foundation can revoke a client at any time. The app then falls
  back to the text view.

## Deploy

Requires Node 20+ and a Cloudflare account with a zone for your domain.

```bash
cd relay
npm ci
npx wrangler login
# In wrangler.toml, replace the placeholder relay.example.com with your own hostname,
# e.g. relay.your-domain.tld (custom domain: Cloudflare creates DNS record and certificate).
npx wrangler secret put QF_CLIENT_ID
npx wrangler secret put QF_CLIENT_SECRET
npm run deploy
curl -s https://relay.your-domain.tld/saglik   # {"tamam":true}
```

Optional vars in `wrangler.toml`: `RATE_LIMIT_PER_MIN` (default 120), and `QF_API` / `QF_OAUTH` to
point at a different Quran Foundation environment (defaults: production).

## Point the app at the relay

The app reads the relay host from the build setting `RELAY_HOST` in `Config/Local.xcconfig` (not
in git), which ends up in the Info key `VermittlerAdresi`:

```
RELAY_HOST = relay.your-domain.tld
```

Write the bare host without `https://` (in xcconfig files `//` starts a comment). Leave it empty
to build without the relay.

## Limits

- **Rate limiting:** the `RATE_LIMITER` binding counts per Cloudflare location; the fallback
  counter (`RATE_LIMIT_PER_MIN`) only per Worker instance. Both slow down a noisy client but are
  not a global cap; use a WAF rate limiting rule for that.
- **Cache API** only works on a custom domain, not on `*.workers.dev` (hence `workers_dev = false`).
  It is per data center, not global.
- **Public is public.** Anyone who knows the hostname can call the routes. Protection comes from
  the fixed route, input validation, caching and rate limiting.

## Develop and test

```bash
npm test             # vitest, no network (fetch and cache are replaced)
npm run typecheck
cp .dev.vars.example .dev.vars && npx wrangler dev   # local run with your own values
```
