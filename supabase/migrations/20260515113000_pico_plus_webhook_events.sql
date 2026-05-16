create table if not exists public.pico_plus_webhook_events (
    event_id text primary key,
    event_type text not null,
    app_user_id uuid,
    payload jsonb not null,
    received_at timestamptz not null default now()
);

alter table public.pico_plus_webhook_events enable row level security;

revoke all on public.pico_plus_webhook_events from public, anon, authenticated;

create or replace function public.user_has_pico_plus(target_user_id uuid)
returns boolean
security definer
stable
set search_path = public
language sql
as $$
    select exists (
        select 1
        from public.user_plus_entitlements
        where user_plus_entitlements.user_id = target_user_id
            and user_plus_entitlements.entitlement_key = 'pico_plus'
            and (
                user_plus_entitlements.status in ('active', 'trialing')
                or (
                    user_plus_entitlements.status in ('canceled', 'past_due')
                    and user_plus_entitlements.current_period_end is not null
                    and user_plus_entitlements.current_period_end > now()
                )
            )
            and (
                user_plus_entitlements.current_period_end is null
                or user_plus_entitlements.current_period_end > now()
            )
    );
$$;

revoke all on function public.user_has_pico_plus(uuid) from public, anon, authenticated;
