-- WatchTrack multi-user foundation.
-- Apply with Supabase migrations after creating the project.
-- No client-supplied role or service-role credential is trusted by this schema.

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text check (display_name is null or char_length(display_name) between 1 and 80),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.watchtrack_state (
  user_id uuid primary key references auth.users(id) on delete cascade,
  state jsonb not null default '{"watchedMovies":[],"tvProgress":{},"wishlist":[]}'::jsonb,
  schema_version integer not null default 1 check (schema_version >= 1),
  revision bigint not null default 1 check (revision >= 1),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint watchtrack_state_is_object check (jsonb_typeof(state) = 'object'),
  constraint watchtrack_state_has_movies check (state ? 'watchedMovies' and jsonb_typeof(state->'watchedMovies') = 'array'),
  constraint watchtrack_state_has_tv_progress check (state ? 'tvProgress' and jsonb_typeof(state->'tvProgress') = 'object'),
  constraint watchtrack_state_has_wishlist check (state ? 'wishlist' and jsonb_typeof(state->'wishlist') = 'array')
);

-- Roles are deliberately isolated from the client-facing profile table.
create table if not exists private.user_roles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  role text not null check (role in ('admin')),
  granted_at timestamptz not null default now(),
  granted_by uuid references auth.users(id) on delete set null
);

revoke all on table private.user_roles from public, anon, authenticated;
grant usage on schema public to authenticated;
revoke all on table public.profiles, public.watchtrack_state from public, anon, authenticated;
grant select on public.profiles to authenticated;
grant update (display_name) on public.profiles to authenticated;
grant select, delete on public.watchtrack_state to authenticated;
grant insert (user_id, state, schema_version) on public.watchtrack_state to authenticated;
grant update (state, schema_version) on public.watchtrack_state to authenticated;
grant all on table public.profiles, public.watchtrack_state to service_role;
grant usage on schema private to service_role;
grant all on table private.user_roles to service_role;

alter table public.profiles enable row level security;
alter table public.profiles force row level security;
alter table public.watchtrack_state enable row level security;
alter table public.watchtrack_state force row level security;
alter table private.user_roles enable row level security;
alter table private.user_roles force row level security;

drop policy if exists "profiles_select_own" on public.profiles;
create policy "profiles_select_own"
  on public.profiles for select to authenticated
  using ((select auth.uid()) = id);

drop policy if exists "profiles_update_own" on public.profiles;
create policy "profiles_update_own"
  on public.profiles for update to authenticated
  using ((select auth.uid()) = id)
  with check ((select auth.uid()) = id);

drop policy if exists "watchtrack_state_select_own" on public.watchtrack_state;
create policy "watchtrack_state_select_own"
  on public.watchtrack_state for select to authenticated
  using ((select auth.uid()) = user_id);

drop policy if exists "watchtrack_state_insert_own" on public.watchtrack_state;
create policy "watchtrack_state_insert_own"
  on public.watchtrack_state for insert to authenticated
  with check ((select auth.uid()) = user_id);

drop policy if exists "watchtrack_state_update_own" on public.watchtrack_state;
create policy "watchtrack_state_update_own"
  on public.watchtrack_state for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

drop policy if exists "watchtrack_state_delete_own" on public.watchtrack_state;
create policy "watchtrack_state_delete_own"
  on public.watchtrack_state for delete to authenticated
  using ((select auth.uid()) = user_id);

-- Only the service role can manage this table. There is intentionally no
-- authenticated-client policy and no public function that changes a role.

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, display_name)
  values (
    new.id,
    nullif(left(coalesce(new.raw_user_meta_data ->> 'name', ''), 80), '')
  )
  on conflict (id) do nothing;

  return new;
end;
$$;

revoke all on function public.handle_new_user() from public, anon, authenticated;

drop trigger if exists on_auth_user_created_watchtrack on auth.users;
create trigger on_auth_user_created_watchtrack
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

revoke all on function public.set_updated_at() from public, anon, authenticated;

drop trigger if exists profiles_set_updated_at on public.profiles;
create trigger profiles_set_updated_at
  before update on public.profiles
  for each row execute procedure public.set_updated_at();

create or replace function public.bump_watchtrack_state_revision()
returns trigger
language plpgsql
set search_path = ''
as $watchtrack$
begin
  new.updated_at = now();
  new.revision = old.revision + 1;
  return new;
end;
$watchtrack$;

revoke all on function public.bump_watchtrack_state_revision() from public, anon, authenticated;

drop trigger if exists watchtrack_state_set_updated_at on public.watchtrack_state;
create trigger watchtrack_state_set_updated_at
  before update on public.watchtrack_state
  for each row execute procedure public.bump_watchtrack_state_revision();

comment on table public.watchtrack_state is
  'One owner-scoped, versioned WatchTrack state document. Keep the legacy JSON shape during migration.';
comment on table private.user_roles is
  'Server-managed roles. Never grant direct access to anon or authenticated clients.';
