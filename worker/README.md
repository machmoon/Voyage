# Voyage Digital Twin Worker

Cloudflare Worker for Voyage's public weather proxy and optional licensed
schedule adapter. It uses no Cloudflare storage products and makes at most one
upstream request per cache miss.

The configuration intentionally omits Wrangler's `limits` block because
custom CPU limits are not supported on the Workers Free plan. Cloudflare's
Free-plan platform limits still apply automatically.

## API

- `GET /v1/health`
- `GET /v1/weather/{airport}` where `airport` is a supported IATA or ICAO code
- `GET /v1/schedules?origin={airport}&date={YYYY-MM-DD}[&destination={airport}]`

Supported airports are BOS/KBOS, JFK/KJFK, MIA/KMIA, SFO/KSFO, LAX/KLAX,
YYZ/CYYZ, YVR/CYVR, and YQR/CYQR.

Weather responses wrap the normalized aviation observation in a `snapshot`
object consumed by the iOS adapter. Successful responses are cached for five
minutes. The upstream is the public Aviation Weather Center METAR API and
receives a custom user agent.

Schedules use `SCHEDULE_PROVIDER_URL` and `SCHEDULE_PROVIDER_KEY` when both are
configured. Without them—or when the provider is unavailable—the endpoint
returns `unavailable: true`, `source: "none"`, and an empty `rows` array so the
app can fall back to its bundled RouteCatalog. Provider responses may expose
either a `rows` or `flights` array using the public row shape; malformed and
unsupported rows are discarded.

## Local development

```bash
npm install
npm run check
npm run dev
```

For a provider-backed local run, copy `.dev.vars.example` to `.dev.vars` and
replace its placeholder values. `.dev.vars` is ignored by Git.

## Deploy

The schedule provider is optional. To enable it, create the Worker first, then
set the two encrypted secrets:

```bash
npx wrangler deploy
npx wrangler secret put SCHEDULE_PROVIDER_URL
npx wrangler secret put SCHEDULE_PROVIDER_KEY
npx wrangler deploy
```

Do not put provider credentials in `wrangler.jsonc`, an Xcode setting, or the
app bundle. Once deployed, set the app's `VoyageAPIBaseURL` Info.plist value (or
the `VOYAGE_API_BASE_URL` process environment variable for local QA) to the
Worker base URL.
