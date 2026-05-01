revoke all on function public.collect_pending_berry_rewards() from public, anon, authenticated;
drop function if exists public.collect_pending_berry_rewards();

revoke all on function public.create_pending_berry_reward(uuid, uuid) from public, anon, authenticated;
drop function if exists public.create_pending_berry_reward(uuid, uuid);

revoke all on function public.random_pending_berry_reward() from public, anon, authenticated;
drop function if exists public.random_pending_berry_reward();

drop policy if exists "Users can read own pending berry rewards" on public.pending_berry_rewards;
revoke all on table public.pending_berry_rewards from public, anon, authenticated;
drop table if exists public.pending_berry_rewards;

notify pgrst, 'reload schema';
