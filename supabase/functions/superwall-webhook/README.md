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

Pico Plus paywalls must be shown after the app identifies Superwall with the authenticated Supabase user ID. The webhook only updates entitlements when the event includes that exact UUID as `appUserId`, `app_user_id`, or a matching `userAttributes.user_id`/`userAttributes.userID` value. Anonymous `$SuperwallAlias` IDs are logged in `pico_plus_webhook_events` but are not used as entitlement owners.

iOS sandbox webhook testing needs TestFlight with a sandbox Apple ID. Local StoreKit configuration purchases do not emit Superwall webhooks.
