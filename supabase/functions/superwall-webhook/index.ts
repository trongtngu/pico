import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

type JsonObject = Record<string, unknown>;

const jsonHeaders = {
  "content-type": "application/json",
};

Deno.serve(async (request) => {
  if (request.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  const configuredSecret = Deno.env.get("SUPERWALL_WEBHOOK_SECRET")?.trim();
  if (configuredSecret && !hasValidWebhookSecret(request, configuredSecret)) {
    return jsonResponse({ error: "Unauthorized" }, 401);
  }

  let payload: JsonObject;
  try {
    payload = await request.json();
  } catch {
    return jsonResponse({ error: "Invalid JSON payload" }, 400);
  }

  const supabaseURL = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseURL || !serviceRoleKey) {
    return jsonResponse({ error: "Missing Supabase function environment" }, 500);
  }

  const eventType = stringValue(payload.event) ?? stringValue(payload.type) ?? stringValue(payload.eventName);
  const eventID = stringValue(payload.id) ?? stringValue(payload.eventId) ?? crypto.randomUUID();
  const data = objectValue(payload.data) ?? {};
  const userAttributes = objectValue(data.userAttributes) ?? {};
  const appUserID = normalizedUUID(
    stringValue(data.appUserId)
      ?? stringValue(data.app_user_id)
      ?? stringValue(data.originalAppUserId)
      ?? stringValue(data.original_app_user_id)
      ?? stringValue(userAttributes.user_id)
      ?? stringValue(userAttributes.userID)
      ?? stringValue(payload.appUserId),
  );

  const supabase = createClient(supabaseURL, serviceRoleKey, {
    auth: {
      persistSession: false,
      autoRefreshToken: false,
    },
  });

  const { error: eventError } = await supabase
    .from("pico_plus_webhook_events")
    .upsert({
      event_id: eventID,
      event_type: eventType ?? "unknown",
      app_user_id: appUserID,
      payload,
    }, { onConflict: "event_id", ignoreDuplicates: true });

  if (eventError) {
    return jsonResponse({ error: eventError.message }, 500);
  }

  if (!eventType || !appUserID) {
    return jsonResponse({ received: true, updatedEntitlement: false });
  }

  const status = entitlementStatus(eventType, data);
  const currentPeriodEnd = timestampValue(
    data.currentPeriodEnd
      ?? data.current_period_end
      ?? data.expiresAt
      ?? data.expires_at
      ?? data.expirationAt
      ?? data.expiration_at
      ?? data.periodEnd
      ?? data.period_end,
  );
  const provider = stringValue(data.store) ?? stringValue(data.provider) ?? "superwall";

  const { error: entitlementError } = await supabase
    .from("user_plus_entitlements")
    .upsert({
      user_id: appUserID,
      entitlement_key: "pico_plus",
      status,
      provider,
      current_period_end: currentPeriodEnd,
    }, { onConflict: "user_id" });

  if (entitlementError) {
    return jsonResponse({ error: entitlementError.message }, 500);
  }

  return jsonResponse({
    received: true,
    updatedEntitlement: true,
    eventType,
    status,
  });
});

function jsonResponse(body: JsonObject, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: jsonHeaders,
  });
}

function hasValidWebhookSecret(request: Request, configuredSecret: string): boolean {
  const authorization = request.headers.get("authorization");
  const bearer = authorization?.startsWith("Bearer ") ? authorization.slice("Bearer ".length) : undefined;
  const headerSecret = request.headers.get("x-superwall-webhook-secret")
    ?? request.headers.get("x-pico-webhook-secret");
  const urlSecret = new URL(request.url).searchParams.get("secret");

  return [bearer, headerSecret, urlSecret].some((candidate) => candidate === configuredSecret);
}

function entitlementStatus(eventType: string, data: JsonObject): string {
  if (numberValue(data.price) !== undefined && numberValue(data.price)! < 0) {
    return "refunded";
  }

  switch (eventType) {
  case "initial_purchase":
  case "renewal":
  case "uncancellation":
  case "product_change":
  case "non_renewing_purchase":
    return periodType(data) === "TRIAL" ? "trialing" : "active";
  case "billing_issue":
    return "past_due";
  case "cancellation":
    return "canceled";
  case "expiration":
    return "expired";
  default:
    return "inactive";
  }
}

function periodType(data: JsonObject): string | undefined {
  return stringValue(data.periodType)?.toUpperCase()
    ?? stringValue(data.period_type)?.toUpperCase();
}

function timestampValue(value: unknown): string | null {
  if (typeof value === "string" && value.trim().length > 0) {
    return value;
  }

  if (typeof value === "number" && Number.isFinite(value)) {
    const milliseconds = value > 10_000_000_000 ? value : value * 1000;
    return new Date(milliseconds).toISOString();
  }

  return null;
}

function normalizedUUID(value: string | undefined): string | null {
  if (!value) {
    return null;
  }

  const match = value.match(/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/i);
  return match?.[0].toLowerCase() ?? null;
}

function objectValue(value: unknown): JsonObject | undefined {
  return value && typeof value === "object" && !Array.isArray(value) ? value as JsonObject : undefined;
}

function stringValue(value: unknown): string | undefined {
  return typeof value === "string" && value.length > 0 ? value : undefined;
}

function numberValue(value: unknown): number | undefined {
  return typeof value === "number" && Number.isFinite(value) ? value : undefined;
}
