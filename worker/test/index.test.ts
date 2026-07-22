import { describe, expect, it, vi } from "vitest";
import { handleRequest } from "../src/index";

const NOW = new Date("2026-07-20T16:00:00.000Z");

class MemoryCache {
  private readonly values = new Map<string, Response>();

  async match(request: Request): Promise<Response | undefined> {
    return this.values.get(request.url)?.clone();
  }

  async put(request: Request, response: Response): Promise<void> {
    this.values.set(request.url, response.clone());
  }
}

function mockedFetch(response: Response | (() => Response)) {
  return vi.fn(async () => typeof response === "function" ? response() : response.clone()) as unknown as typeof fetch;
}

function request(path: string, init?: RequestInit): Request {
  return new Request(`https://voyage.test${path}`, init);
}

describe("routing and protocol behavior", () => {
  it("reports health and whether schedules are configured", async () => {
    const response = await handleRequest(request("/v1/health"), {}, undefined, { now: () => NOW });
    expect(response.status).toBe(200);
    expect(response.headers.get("cache-control")).toBe("no-store");
    expect(await response.json()).toEqual({
      status: "ok",
      version: "v1",
      timestamp: NOW.toISOString(),
      services: { weather: "available", schedules: "fallback" },
    });
  });

  it("handles CORS preflight", async () => {
    const response = await handleRequest(request("/v1/weather/SFO", { method: "OPTIONS" }));
    expect(response.status).toBe(204);
    expect(response.headers.get("access-control-allow-methods")).toBe("GET, OPTIONS");
  });

  it("rejects unsupported methods with an Allow header", async () => {
    const response = await handleRequest(request("/v1/health", { method: "POST" }));
    expect(response.status).toBe(405);
    expect(response.headers.get("allow")).toBe("GET, OPTIONS");
    expect(await response.json()).toMatchObject({ error: { code: "METHOD_NOT_ALLOWED" } });
  });
});

describe("weather", () => {
  const report = {
    icaoId: "KSFO",
    reportTime: "2026-07-20T15:56:00.000Z",
    wdir: 280,
    wspd: 18,
    wgst: 25,
    visib: "10+",
    temp: 17,
    dewp: 12,
    wxString: "-RA BR",
    clouds: [{ cover: "SCT", base: 2500 }, { cover: "BKN", base: 1200 }],
    rawOb: "KSFO 201556Z 28018G25KT 10SM -RA BR SCT025 BKN012 17/12",
    fltCat: "MVFR",
  };

  it("maps AWC JSON into the public weather envelope", async () => {
    const upstreamFetch = mockedFetch(new Response(JSON.stringify([report]), { status: 200 }));
    const response = await handleRequest(request("/v1/weather/SFO"), {}, undefined, {
      fetch: upstreamFetch,
      cache: new MemoryCache(),
      now: () => NOW,
    });

    expect(response.status).toBe(200);
    expect(response.headers.get("cache-control")).toContain("max-age=300");
    expect(await response.json()).toEqual({
      snapshot: {
        icao: "KSFO",
        metarTime: "2026-07-20T15:56:00.000Z",
        wind: { direction: 280, speed: 18, gust: 25 },
        visibility: 10,
        cloudLayers: [
          { coverage: "SCT", altitude: 2500 },
          { coverage: "BKN", altitude: 1200 },
        ],
        ceiling: 1200,
        temperature: 17,
        dewpoint: 12,
        precipitation: "light",
        flightCategory: "MVFR",
        raw: report.rawOb,
        source: "aviationweather.gov",
      },
    });

    const [url, init] = (upstreamFetch as unknown as ReturnType<typeof vi.fn>).mock.calls[0];
    expect(String(url)).toContain("ids=KSFO");
    expect(String(url)).toContain("format=json");
    expect((init.headers as Record<string, string>)["user-agent"]).toContain("VoyageDigitalTwin");
  });

  it("also accepts supported ICAO codes", async () => {
    const upstreamFetch = mockedFetch(new Response(JSON.stringify([report])));
    const response = await handleRequest(request("/v1/weather/KSFO"), {}, undefined, { fetch: upstreamFetch });
    expect(response.status).toBe(200);
    expect(await response.json()).toMatchObject({ snapshot: { icao: "KSFO" } });
  });

  it("serves a normalized airport lookup from cache", async () => {
    const cache = new MemoryCache();
    const upstreamFetch = mockedFetch(new Response(JSON.stringify([report])));
    await handleRequest(request("/v1/weather/SFO"), {}, undefined, { fetch: upstreamFetch, cache });
    const second = await handleRequest(request("/v1/weather/KSFO"), {}, undefined, { fetch: upstreamFetch, cache });
    expect(second.status).toBe(200);
    expect(upstreamFetch).toHaveBeenCalledTimes(1);
  });

  it("rejects unsupported airports before calling upstream", async () => {
    const upstreamFetch = mockedFetch(new Response("[]"));
    const response = await handleRequest(request("/v1/weather/XXX"), {}, undefined, { fetch: upstreamFetch });
    expect(response.status).toBe(400);
    expect(upstreamFetch).not.toHaveBeenCalled();
  });

  it("distinguishes no report, malformed JSON, and upstream errors", async () => {
    const noReport = await handleRequest(request("/v1/weather/SFO"), {}, undefined, {
      fetch: mockedFetch(new Response(null, { status: 204 })),
    });
    expect(noReport.status).toBe(404);

    const malformed = await handleRequest(request("/v1/weather/SFO"), {}, undefined, {
      fetch: mockedFetch(new Response("not-json", { status: 200 })),
    });
    expect(malformed.status).toBe(502);

    const upstream = await handleRequest(request("/v1/weather/SFO"), {}, undefined, {
      fetch: mockedFetch(new Response("error", { status: 429 })),
    });
    expect(upstream.status).toBe(502);
    expect(upstream.headers.get("cache-control")).toBe("no-store");
  });
});

describe("schedules", () => {
  it("returns an explicit unavailable response without provider secrets", async () => {
    const response = await handleRequest(
      request("/v1/schedules?origin=SFO&date=2026-07-20"),
      {},
      undefined,
      { cache: undefined },
    );
    expect(response.status).toBe(200);
    expect(response.headers.get("cache-control")).toBe("public, max-age=60");
    expect(await response.json()).toEqual({
      origin: "KSFO",
      date: "2026-07-20",
      rows: [],
      source: "none",
      freshness: null,
      unavailable: true,
    });
  });

  it("validates real calendar dates and airport inputs", async () => {
    const badDate = await handleRequest(request("/v1/schedules?origin=SFO&date=2026-02-30"));
    expect(badDate.status).toBe(400);
    expect(await badDate.json()).toMatchObject({ error: { code: "INVALID_DATE" } });

    const badOrigin = await handleRequest(request("/v1/schedules?origin=XXX&date=2026-07-20"));
    expect(badOrigin.status).toBe(400);

    const sameDestination = await handleRequest(request("/v1/schedules?origin=SFO&destination=KSFO&date=2026-07-20"));
    expect(sameDestination.status).toBe(400);
  });

  it("normalizes, filters, and limits provider rows", async () => {
    const rows = [
      {
        flightNumber: "UA 201",
        airline: "United",
        origin: "KSFO",
        destination: "KLAX",
        scheduledDeparture: "2026-07-20T18:00:00-07:00",
        aircraftType: "B738",
        gate: "F12",
        status: "scheduled",
      },
      {
        flightNumber: "AC 999",
        airline: "Air Canada",
        origin: "YYZ",
        destination: "YVR",
        scheduledDeparture: "2026-07-20T18:00:00Z",
      },
      { flightNumber: "broken" },
    ];
    const providerFetch = mockedFetch(new Response(JSON.stringify({
      flights: rows,
      source: "licensed-provider",
      freshness: "2026-07-20T15:30:00Z",
    })));

    const response = await handleRequest(
      request("/v1/schedules?origin=KSFO&destination=LAX&date=2026-07-20"),
      { SCHEDULE_PROVIDER_URL: "https://provider.example/flights", SCHEDULE_PROVIDER_KEY: "secret" },
      undefined,
      { fetch: providerFetch, now: () => NOW },
    );
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({
      origin: "KSFO",
      date: "2026-07-20",
      rows: [{
        flightNumber: "UA 201",
        airline: "United",
        origin: "KSFO",
        destination: "KLAX",
        scheduledDeparture: "2026-07-21T01:00:00.000Z",
        aircraftType: "B738",
        gate: "F12",
        status: "scheduled",
      }],
      source: "licensed-provider",
      freshness: "2026-07-20T15:30:00.000Z",
      unavailable: false,
    });

    const [url, init] = (providerFetch as unknown as ReturnType<typeof vi.fn>).mock.calls[0];
    expect(String(url)).toBe("https://provider.example/flights?origin=KSFO&date=2026-07-20&destination=KLAX");
    expect((init.headers as Record<string, string>).authorization).toBe("Bearer secret");
  });

  it("falls back cleanly when the provider fails", async () => {
    const response = await handleRequest(
      request("/v1/schedules?origin=SFO&date=2026-07-20"),
      { SCHEDULE_PROVIDER_URL: "https://provider.example/flights", SCHEDULE_PROVIDER_KEY: "secret" },
      undefined,
      { fetch: mockedFetch(new Response("quota", { status: 429 })), cache: undefined },
    );
    expect(response.status).toBe(200);
    expect(await response.json()).toMatchObject({ source: "none", rows: [], unavailable: true });
  });

  it("falls back when a successful provider response has the wrong schema", async () => {
    const response = await handleRequest(
      request("/v1/schedules?origin=SFO&destination=LAX&date=2026-07-20"),
      { SCHEDULE_PROVIDER_URL: "https://provider.example/flights", SCHEDULE_PROVIDER_KEY: "secret" },
      undefined,
      { fetch: mockedFetch(new Response(JSON.stringify({ data: "unexpected" }))), cache: undefined },
    );
    expect(response.status).toBe(200);
    expect(await response.json()).toMatchObject({ source: "none", rows: [], unavailable: true });
  });

  it("rejects a non-HTTPS provider configuration", async () => {
    const response = await handleRequest(
      request("/v1/schedules?origin=SFO&date=2026-07-20"),
      { SCHEDULE_PROVIDER_URL: "http://provider.example/flights", SCHEDULE_PROVIDER_KEY: "secret" },
    );
    expect(response.status).toBe(503);
    expect(await response.json()).toMatchObject({ error: { code: "SCHEDULE_CONFIGURATION" } });
  });
});
