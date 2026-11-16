import { createClient } from "npm:@supabase/supabase-js@2";

const TMDB_API = "https://api.themoviedb.org/3";
const MAX_BODY_BYTES = 16 * 1024;
const MAX_RESPONSE_BYTES = 2 * 1024 * 1024;
const ALLOWED_QUERY_KEYS = new Set([
  "append_to_response", "include_adult", "language", "page", "query", "region",
]);

function json(body: unknown, status: number, origin: string | null, allowed: boolean) {
  const headers = new Headers({
    "Content-Type": "application/json; charset=utf-8",
    "Cache-Control": "no-store",
    "X-Content-Type-Options": "nosniff",
    "Vary": "Origin",
  });
  if (origin && allowed) {
    headers.set("Access-Control-Allow-Origin", origin);
    headers.set("Access-Control-Allow-Methods", "POST, OPTIONS");
    headers.set("Access-Control-Allow-Headers", "authorization, apikey, content-type, x-client-info");
    headers.set("Access-Control-Max-Age", "600");
  }
  return new Response(JSON.stringify(body), { status, headers });
}

function allowedOrigins() {
  return (Deno.env.get("WATCHTRACK_ALLOWED_ORIGINS") ?? "")
    .split(",").map((value) => value.trim()).filter(Boolean);
}

function isAllowedTmdbPath(path: unknown): path is string {
  if (typeof path !== "string" || path.length > 160 || !path.startsWith("/") || path.includes("..")) return false;
  return /^\/(configuration|search\/multi|trending\/all\/day|movie\/\d+(?:\/watch\/providers)?|tv\/\d+(?:\/season\/\d+|\/watch\/providers)?)$/.test(path);
}

function validQuery(value: unknown): value is Record<string, string | number | boolean> {
  if (!value || typeof value !== "object" || Array.isArray(value)) return false;
  const entries = Object.entries(value as Record<string, unknown>);
  if (entries.length > 12) return false;
  return entries.every(([key, item]) =>
    ALLOWED_QUERY_KEYS.has(key) &&
    (typeof item === "string" || typeof item === "number" || typeof item === "boolean") &&
    String(item).length <= 300
  );
}

Deno.serve(async (request: Request) => {
  const origin = request.headers.get("origin");
  const origins = allowedOrigins();
  const originAllowed = !origin || origins.includes(origin);

  if (origin && !originAllowed) return json({ error: "Origin not allowed" }, 403, origin, false);
  if (request.method === "OPTIONS") {
    if (!origin) return new Response(null, { status: 204 });
    return new Response(null, {
      status: 204,
      headers: {
        "Access-Control-Allow-Origin": origin,
        "Access-Control-Allow-Methods": "POST, OPTIONS",
        "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
        "Access-Control-Max-Age": "600",
        "Vary": "Origin",
      },
    });
  }
  if (request.method !== "POST") return json({ error: "Method not allowed" }, 405, origin, originAllowed);

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const tmdbToken = Deno.env.get("TMDB_API_READ_ACCESS_TOKEN");
  if (!supabaseUrl || !anonKey || !serviceRoleKey || !tmdbToken) {
    return json({ error: "Server configuration is incomplete" }, 503, origin, originAllowed);
  }

  const authorization = request.headers.get("authorization") ?? "";
  const match = authorization.match(/^Bearer\s+(.+)$/i);
  if (!match) return json({ error: "Authentication required" }, 401, origin, originAllowed);

  const authClient = createClient(supabaseUrl, anonKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: authData, error: authError } = await authClient.auth.getUser(match[1]);
  if (authError || !authData.user) return json({ error: "Invalid or expired session" }, 401, origin, originAllowed);

  let rawBody: string;
  try {
    const declaredLength = Number(request.headers.get("content-length") ?? "0");
    if (declaredLength > MAX_BODY_BYTES) return json({ error: "Request too large" }, 413, origin, originAllowed);
    rawBody = await request.text();
    if (new TextEncoder().encode(rawBody).byteLength > MAX_BODY_BYTES) {
      return json({ error: "Request too large" }, 413, origin, originAllowed);
    }
  } catch {
    return json({ error: "Invalid request body" }, 400, origin, originAllowed);
  }

  let body: unknown;
  try { body = JSON.parse(rawBody); } catch { return json({ error: "Invalid JSON" }, 400, origin, originAllowed); }
  if (!body || typeof body !== "object" || Array.isArray(body)) {
    return json({ error: "Invalid request" }, 400, origin, originAllowed);
  }
  const payload = body as Record<string, unknown>;
  if (!isAllowedTmdbPath(payload.path) || !validQuery(payload.query ?? {})) {
    return json({ error: "Unsupported catalogue request" }, 400, origin, originAllowed);
  }

  const serviceClient = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: withinLimit, error: rateError } = await serviceClient.rpc("consume_tmdb_rate_limit", {
    p_user_id: authData.user.id,
    p_limit: 120,
    p_window_seconds: 60,
  });
  if (rateError || withinLimit !== true) {
    return json({ error: "Request limit reached. Please try again shortly." }, 429, origin, originAllowed);
  }

  const upstreamUrl = new URL(tmdbPath(payload.path));
  for (const [key, value] of Object.entries((payload.query ?? {}) as Record<string, string | number | boolean>)) {
    upstreamUrl.searchParams.set(key, String(value));
  }

  try {
    const upstream = await fetch(upstreamUrl, {
      method: "GET",
      headers: { "Authorization": `Bearer ${tmdbToken}`, "Accept": "application/json" },
      signal: AbortSignal.timeout(12_000),
    });
    const contentLength = Number(upstream.headers.get("content-length") ?? "0");
    if (contentLength > MAX_RESPONSE_BYTES) return json({ error: "Catalogue response too large" }, 502, origin, originAllowed);
    const responseText = await upstream.text();
    if (new TextEncoder().encode(responseText).byteLength > MAX_RESPONSE_BYTES) {
      return json({ error: "Catalogue response too large" }, 502, origin, originAllowed);
    }
    if (!upstream.ok) return json({ error: "Catalogue provider request failed", status: upstream.status }, 502, origin, originAllowed);
    try { JSON.parse(responseText); } catch { return json({ error: "Catalogue provider returned an invalid response" }, 502, origin, originAllowed); }
    return new Response(responseText, {
      status: 200,
      headers: {
        "Content-Type": "application/json; charset=utf-8",
        "Cache-Control": "no-store",
        "X-Content-Type-Options": "nosniff",
        "Vary": "Origin",
        ...(origin ? { "Access-Control-Allow-Origin": origin } : {}),
      },
    });
  } catch {
    return json({ error: "Catalogue provider is temporarily unavailable" }, 502, origin, originAllowed);
  }
});

function tmdbPath(path: string): string {
  return `${TMDB_API}${path}`;
}
