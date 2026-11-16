-- Per-user fixed-window rate limiting for the authenticated TMDB proxy.
create table if not exists private.tmdb_rate_limits (
  user_id uuid primary key references auth.users(id) on delete cascade,
  window_started_at timestamptz not null default now(),
  request_count integer not null default 0 check (request_count >= 0)
);

revoke all on table private.tmdb_rate_limits from public, anon, authenticated;
grant all on table private.tmdb_rate_limits to service_role;

create or replace function public.consume_tmdb_rate_limit(
  p_user_id uuid,
  p_limit integer default 120,
  p_window_seconds integer default 60
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  if p_user_id is null or p_limit < 1 or p_limit > 1000
     or p_window_seconds < 1 or p_window_seconds > 3600 then
    return false;
  end if;

  insert into private.tmdb_rate_limits as current_limit
    (user_id, window_started_at, request_count)
  values (p_user_id, now(), 1)
  on conflict (user_id) do update
    set window_started_at = case
          when current_limit.window_started_at <= now() - make_interval(secs => p_window_seconds)
            then now()
          else current_limit.window_started_at
        end,
        request_count = case
          when current_limit.window_started_at <= now() - make_interval(secs => p_window_seconds)
            then 1
          else current_limit.request_count + 1
        end
  returning request_count into v_count;

  return v_count <= p_limit;
end;
$$;

revoke all on function public.consume_tmdb_rate_limit(uuid, integer, integer) from public, anon, authenticated;
grant execute on function public.consume_tmdb_rate_limit(uuid, integer, integer) to service_role;
