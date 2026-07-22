const AWC_METAR_URL = "https://aviationweather.gov/api/data/metar";
const USER_AGENT = "VoyageDigitalTwin/1.0 (iOS; contact=voyage-support)";
const WEATHER_TTL_SECONDS = 300;
const SCHEDULE_TTL_SECONDS = 300;
const UNAVAILABLE_TTL_SECONDS = 60;

const IATA_TO_ICAO = {
  BOS: "KBOS",
  JFK: "KJFK",
  MIA: "KMIA",
  SFO: "KSFO",
  LAX: "KLAX",
  YYZ: "CYYZ",
  YVR: "CYVR",
  YQR: "CYQR",
} as const;

type IATACode = keyof typeof IATA_TO_ICAO;
type ScheduleStatus = "scheduled" | "typical";
type CloudCoverage = "FEW" | "SCT" | "BKN" | "OVC" | "VV";
type Precipitation = "none" | "light" | "moderate" | "heavy";

interface Env {
  SCHEDULE_PROVIDER_URL?: string;
  SCHEDULE_PROVIDER_KEY?: string;
}

interface CloudLayer {
  cover?: unknown;
  base?: unknown;
}

interface MetarReport {
  icaoId?: unknown;
  reportTime?: unknown;
  wdir?: unknown;
  wspd?: unknown;
  wgst?: unknown;
  visib?: unknown;
  temp?: unknown;
  dewp?: unknown;
  wxString?: unknown;
  clouds?: unknown;
  rawOb?: unknown;
  fltCat?: unknown;
}

interface WeatherSnapshot {
  icao: string;
  metarTime: string;
  wind: {
    direction: number | null;
    speed: number | null;
    gust: number | null;
  };
  visibility: number | null;
  cloudLayers: Array<{ coverage: CloudCoverage; altitude: number }>;
  ceiling: number | null;
  temperature: number | null;
  dewpoint: number | null;
  precipitation: Precipitation;
  flightCategory: string | null;
  raw: string | null;
  source: "aviationweather.gov";
}

interface ScheduleRow {
  flightNumber: string;
  airline: string;
  origin: string;
  destination: string;
  scheduledDeparture: string;
  aircraftType: string | null;
  gate: string | null;
  status: ScheduleStatus;
}

interface ScheduleResponse {
  origin: string;
  date: string;
  rows: ScheduleRow[];
  source: string;
  freshness: string | null;
  unavailable: boolean;
}

interface CacheLike {
  match(request: Request): Promise<Response | undefined>;
  put(request: Request, response: Response): Promise<void>;
}

interface ExecutionContextLike {
  waitUntil(promise: Promise<unknown>): void;
}

interface Dependencies {
  fetch: typeof fetch;
  cache?: CacheLike;
  now: () => Date;
}

const CORS_HEADERS: Record<string, string> = {
  "access-control-allow-origin": "*",
  "access-control-allow-methods": "GET, OPTIONS",
  "access-control-allow-headers": "Content-Type",
  "access-control-max-age": "86400",
};

function json(value: unknown, status = 200, cacheControl = "no-store", extraHeaders: HeadersInit = {}): Response {
  return new Response(JSON.stringify(value), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": cacheControl,
      "x-content-type-options": "nosniff",
      ...CORS_HEADERS,
      ...Object.fromEntries(new Headers(extraHeaders)),
    },
  });
}

function errorResponse(code: string, message: string, status: number, extraHeaders: HeadersInit = {}): Response {
  return json({ error: { code, message } }, status, "no-store", extraHeaders);
}

function resolveAirport(value: string): { iata: IATACode; icao: string } | null {
  const code = value.toUpperCase();
  if (code in IATA_TO_ICAO) {
    const iata = code as IATACode;
    return { iata, icao: IATA_TO_ICAO[iata] };
  }
  const entry = Object.entries(IATA_TO_ICAO).find(([, icao]) => icao === code);
  return entry ? { iata: entry[0] as IATACode, icao: entry[1] } : null;
}

function validDate(value: string): boolean {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  const [year, month, day] = value.split("-").map(Number);
  const date = new Date(Date.UTC(year, month - 1, day));
  return date.getUTCFullYear() === year && date.getUTCMonth() === month - 1 && date.getUTCDate() === day;
}

function finiteNumber(value: unknown): number | null {
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (typeof value === "string" && value.trim() !== "") {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : null;
  }
  return null;
}

function visibilityMiles(value: unknown): number | null {
  if (value === "10+") return 10;
  return finiteNumber(value);
}

function cloudLayers(value: unknown): CloudLayer[] {
  return Array.isArray(value)
    ? value.filter((layer): layer is CloudLayer => typeof layer === "object" && layer !== null)
    : [];
}

function parsedCloudLayers(report: MetarReport): WeatherSnapshot["cloudLayers"] {
  const supported = new Set<CloudCoverage>(["FEW", "SCT", "BKN", "OVC", "VV"]);
  return cloudLayers(report.clouds).flatMap(layer => {
    const coverage = typeof layer.cover === "string" ? layer.cover.toUpperCase() as CloudCoverage : null;
    const altitude = finiteNumber(layer.base);
    return coverage && supported.has(coverage) && altitude !== null && altitude >= 0
      ? [{ coverage, altitude }]
      : [];
  });
}

function precipitation(report: MetarReport): Precipitation {
  const weather = typeof report.wxString === "string" ? report.wxString.toUpperCase() : "";
  if (!/(RA|DZ|SN|SG|PL|GR|GS|UP)/.test(weather)) return "none";
  if (weather.includes("+")) return "heavy";
  if (weather.includes("-")) return "light";
  return "moderate";
}

function flightCategory(ceiling: number | null, visibility: number | null): string {
  const miles = visibility ?? 10;
  if ((ceiling !== null && ceiling < 500) || miles < 1) return "LIFR";
  if ((ceiling !== null && ceiling < 1000) || miles < 3) return "IFR";
  if ((ceiling !== null && ceiling < 3000) || miles < 5) return "MVFR";
  return "VFR";
}

function validISODate(value: unknown, fallback: Date): string {
  if (typeof value === "string") {
    const parsed = new Date(value);
    if (!Number.isNaN(parsed.valueOf())) return parsed.toISOString();
  }
  return fallback.toISOString();
}

function weatherSnapshot(report: MetarReport, airport: { iata: IATACode; icao: string }, now: Date): WeatherSnapshot {
  const layers = parsedCloudLayers(report);
  const ceilingLayers = layers.filter(layer => ["BKN", "OVC", "VV"].includes(layer.coverage));
  const ceiling = ceilingLayers.length > 0 ? Math.min(...ceilingLayers.map(layer => layer.altitude)) : null;
  const visibility = visibilityMiles(report.visib);
  return {
    icao: airport.icao,
    metarTime: validISODate(report.reportTime, now),
    wind: {
      direction: finiteNumber(report.wdir),
      speed: finiteNumber(report.wspd),
      gust: finiteNumber(report.wgst),
    },
    visibility,
    cloudLayers: layers,
    ceiling,
    temperature: finiteNumber(report.temp),
    dewpoint: finiteNumber(report.dewp),
    precipitation: precipitation(report),
    flightCategory: typeof report.fltCat === "string" ? report.fltCat : flightCategory(ceiling, visibility),
    raw: typeof report.rawOb === "string" ? report.rawOb : null,
    source: "aviationweather.gov",
  };
}

function cacheKey(path: string): Request {
  return new Request(`https://voyage-cache.invalid${path}`, { method: "GET" });
}

async function store(cache: CacheLike | undefined, key: Request, response: Response, ctx?: ExecutionContextLike): Promise<void> {
  if (!cache) return;
  const operation = cache.put(key, response.clone());
  if (ctx) ctx.waitUntil(operation);
  else await operation;
}

async function handleWeather(
  code: string,
  ctx: ExecutionContextLike | undefined,
  dependencies: Dependencies,
): Promise<Response> {
  const airport = resolveAirport(code);
  if (!airport) return errorResponse("INVALID_AIRPORT", "Invalid or unsupported airport code", 400);

  const key = cacheKey(`/v1/weather/${airport.icao}`);
  const cached = await dependencies.cache?.match(key);
  if (cached) return cached;

  const upstream = new URL(AWC_METAR_URL);
  upstream.searchParams.set("ids", airport.icao);
  upstream.searchParams.set("format", "json");

  let response: Response;
  try {
    response = await dependencies.fetch(upstream, {
      headers: { "user-agent": USER_AGENT, accept: "application/json" },
    });
  } catch (error) {
    console.error("AWC METAR fetch failed", error);
    return errorResponse("WEATHER_UNAVAILABLE", "Weather service temporarily unavailable", 503);
  }

  if (response.status === 204) {
    return errorResponse("NO_METAR", `No METAR data available for ${airport.icao}`, 404);
  }
  if (!response.ok) {
    return errorResponse("WEATHER_UPSTREAM", "Upstream weather service unavailable", 502);
  }

  let reports: unknown;
  try {
    reports = await response.json();
  } catch {
    return errorResponse("WEATHER_PARSE", "Unable to parse weather service response", 502);
  }
  if (!Array.isArray(reports) || reports.length === 0 || typeof reports[0] !== "object" || reports[0] === null) {
    return errorResponse("NO_METAR", `No METAR data available for ${airport.icao}`, 404);
  }

  const snapshot = weatherSnapshot(reports[0] as MetarReport, airport, dependencies.now());
  const result = json({ snapshot }, 200, `public, max-age=${WEATHER_TTL_SECONDS}, stale-while-revalidate=600`);
  await store(dependencies.cache, key, result, ctx);
  return result;
}

function optionalString(value: unknown): string | null {
  return typeof value === "string" && value.trim() !== "" ? value.trim() : null;
}

function normalizeScheduleRow(value: unknown, expectedOrigin: string): ScheduleRow | null {
  if (typeof value !== "object" || value === null) return null;
  const row = value as Record<string, unknown>;
  const flightNumber = optionalString(row.flightNumber);
  const airline = optionalString(row.airline ?? row.carrierName);
  const origin = resolveAirport(optionalString(row.origin) ?? "");
  const destination = resolveAirport(optionalString(row.destination) ?? "");
  const departureValue = optionalString(row.scheduledDeparture ?? row.departure);
  if (!flightNumber || !airline || !origin || !destination || origin.icao !== expectedOrigin || !departureValue) return null;

  const departure = new Date(departureValue);
  if (Number.isNaN(departure.valueOf())) return null;
  const status: ScheduleStatus = row.status === "typical" ? "typical" : "scheduled";
  return {
    flightNumber,
    airline,
    origin: origin.icao,
    destination: destination.icao,
    scheduledDeparture: departure.toISOString(),
    aircraftType: optionalString(row.aircraftType),
    gate: optionalString(row.gate),
    status,
  };
}

async function handleSchedules(
  url: URL,
  env: Env,
  ctx: ExecutionContextLike | undefined,
  dependencies: Dependencies,
): Promise<Response> {
  const origin = resolveAirport(url.searchParams.get("origin") ?? "");
  const date = url.searchParams.get("date") ?? "";
  if (!origin) return errorResponse("INVALID_AIRPORT", "Invalid or unsupported origin airport", 400);
  if (!validDate(date)) return errorResponse("INVALID_DATE", "Invalid date; expected a real YYYY-MM-DD date", 400);

  const destinationParam = url.searchParams.get("destination");
  const destination = destinationParam ? resolveAirport(destinationParam) : null;
  if (destinationParam && (!destination || destination.iata === origin.iata)) {
    return errorResponse("INVALID_DESTINATION", "Invalid or unsupported destination airport", 400);
  }

  const suffix = destination ? `/${destination.icao}` : "";
  const key = cacheKey(`/v1/schedules/${origin.icao}/${date}${suffix}`);
  const cached = await dependencies.cache?.match(key);
  if (cached) return cached;

  if (env.SCHEDULE_PROVIDER_URL && env.SCHEDULE_PROVIDER_KEY) {
    let providerURL: URL;
    try {
      providerURL = new URL(env.SCHEDULE_PROVIDER_URL);
      if (providerURL.protocol !== "https:") throw new Error("Schedule provider must use HTTPS");
    } catch {
      return errorResponse("SCHEDULE_CONFIGURATION", "Schedule provider is misconfigured", 503);
    }
    providerURL.searchParams.set("origin", origin.icao);
    providerURL.searchParams.set("date", date);
    if (destination) providerURL.searchParams.set("destination", destination.icao);

    try {
      const providerResponse = await dependencies.fetch(providerURL, {
        headers: {
          authorization: `Bearer ${env.SCHEDULE_PROVIDER_KEY}`,
          "user-agent": USER_AGENT,
          accept: "application/json",
        },
      });
      if (providerResponse.ok) {
        const payload = await providerResponse.json() as { rows?: unknown; flights?: unknown; source?: unknown; freshness?: unknown };
        const candidates = Array.isArray(payload.rows) ? payload.rows : Array.isArray(payload.flights) ? payload.flights : null;
        if (!candidates) throw new Error("Schedule provider returned an invalid payload");
        const rows = candidates
          .map(row => normalizeScheduleRow(row, origin.icao))
          .filter((row): row is ScheduleRow => row !== null)
          .filter(row => !destination || row.destination === destination.icao)
          .slice(0, 10);
        if (candidates.length > 0 && rows.length === 0) {
          throw new Error("Schedule provider returned no usable rows");
        }

        const body: ScheduleResponse = {
          origin: origin.icao,
          date,
          rows,
          source: optionalString(payload.source) ?? providerURL.hostname,
          freshness: validISODate(payload.freshness, dependencies.now()),
          unavailable: false,
        };
        const result = json(body, 200, `public, max-age=${SCHEDULE_TTL_SECONDS}`);
        await store(dependencies.cache, key, result, ctx);
        return result;
      }
    } catch {
      // Provider errors deliberately fall through to the explicit local-fallback signal.
    }
  }

  const body: ScheduleResponse = {
    origin: origin.icao,
    date,
    rows: [],
    source: "none",
    freshness: null,
    unavailable: true,
  };
  const result = json(body, 200, `public, max-age=${UNAVAILABLE_TTL_SECONDS}`);
  await store(dependencies.cache, key, result, ctx);
  return result;
}

function runtimeCache(): CacheLike | undefined {
  return typeof caches === "undefined" ? undefined : caches.default;
}

export async function handleRequest(
  request: Request,
  env: Env = {},
  ctx?: ExecutionContextLike,
  overrides: Partial<Dependencies> = {},
): Promise<Response> {
  const dependencies: Dependencies = {
    fetch: overrides.fetch ?? ((input, init) => fetch(input, init)),
    cache: Object.prototype.hasOwnProperty.call(overrides, "cache") ? overrides.cache : runtimeCache(),
    now: overrides.now ?? (() => new Date()),
  };

  if (request.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: CORS_HEADERS });
  }
  if (request.method !== "GET") {
    return errorResponse("METHOD_NOT_ALLOWED", "Method not allowed", 405, { allow: "GET, OPTIONS" });
  }

  const url = new URL(request.url);
  if (url.pathname === "/v1/health") {
    return json({
      status: "ok",
      version: "v1",
      timestamp: dependencies.now().toISOString(),
      services: {
        weather: "available",
        schedules: env.SCHEDULE_PROVIDER_URL && env.SCHEDULE_PROVIDER_KEY ? "configured" : "fallback",
      },
    });
  }

  const weatherMatch = url.pathname.match(/^\/v1\/weather\/([A-Za-z]{3,4})$/);
  if (weatherMatch) return handleWeather(weatherMatch[1], ctx, dependencies);
  if (url.pathname === "/v1/schedules") return handleSchedules(url, env, ctx, dependencies);
  return errorResponse("NOT_FOUND", "Not found", 404);
}

export default {
  fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    return handleRequest(request, env, ctx);
  },
} satisfies ExportedHandler<Env>;
