# Superwall Webhook

Supabase Edge Function endpoint for Pico Plus subscription lifecycle events.

Required deployed secrets:

- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY`
- `SUPERWALL_WEBHOOK_SECRET`

Configure the Superwall webhook to call this function with one of:

- `Authorization: Bearer <SUPERWALL_WEBHOOK_SECRET>`
- `x-superwall-webhook-secret: <SUPERWALL_WEBHOOK_SECRET>`
- `?secret=<SUPERWALL_WEBHOOK_SECRET>`

iOS sandbox webhook testing needs TestFlight with a sandbox Apple ID. Local StoreKit configuration purchases do not emit Superwall webhooks.
