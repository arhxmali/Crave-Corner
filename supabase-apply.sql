-- ============================================================
-- Mr. Pizza / CraveCorner - full Supabase schema (idempotent)
-- Run in: Supabase Dashboard > SQL Editor > New query
-- Safe to run more than once.
-- ============================================================

create extension if not exists "uuid-ossp";

-- ------------------------------------------------------------
-- orders
-- ------------------------------------------------------------
create table if not exists public.orders (
  id text primary key,
  order_code text not null unique,
  customer_name text not null,
  customer_phone text not null,
  delivery_address text not null,
  items jsonb not null default '[]'::jsonb,
  total numeric(10, 2) not null,
  status text not null default 'placed'
    check (status in ('placed', 'confirmed', 'preparing', 'ready', 'delivered', 'cancelled')),
  confirmed_by text,
  note text,
  latitude numeric(10, 7),
  longitude numeric(10, 7),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create index if not exists idx_orders_status on public.orders(status);
create index if not exists idx_orders_created_at on public.orders(created_at desc);
create index if not exists idx_orders_order_code on public.orders(order_code);

alter table public.orders enable row level security;

drop policy if exists "Service role full access" on public.orders;
create policy "Service role full access" on public.orders
  for all to service_role using (true) with check (true);

drop policy if exists "Staff read all orders" on public.orders;
create policy "Staff read all orders" on public.orders
  for select to authenticated using (true);

drop policy if exists "Staff update order status" on public.orders;
create policy "Staff update order status" on public.orders
  for update to authenticated using (true) with check (true);

-- Public order tracking page reads with the publishable key.
-- Order ids are nanoid(24), i.e. unguessable.
drop policy if exists "Anyone can view orders by ID" on public.orders;
create policy "Anyone can view orders by ID" on public.orders
  for select to anon using (true);

create or replace function public.update_updated_at_column()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

drop trigger if exists update_orders_updated_at on public.orders;
create trigger update_orders_updated_at
  before update on public.orders
  for each row execute function public.update_updated_at_column();

-- ------------------------------------------------------------
-- staff (one row per Supabase Auth user allowed into the console)
-- ------------------------------------------------------------
create table if not exists public.staff (
  id uuid primary key references auth.users(id) on delete cascade,
  email text not null unique,
  name text not null,
  role text not null default 'staff' check (role in ('admin', 'staff')),
  created_at timestamptz not null default now()
);

alter table public.staff enable row level security;

drop policy if exists "Staff can read own data" on public.staff;
create policy "Staff can read own data" on public.staff
  for select to authenticated using (auth.uid() = id);

drop policy if exists "Staff can update own data" on public.staff;
create policy "Staff can update own data" on public.staff
  for update to authenticated using (auth.uid() = id) with check (auth.uid() = id);

drop policy if exists "Service role full access" on public.staff;
create policy "Service role full access" on public.staff
  for all to service_role using (true) with check (true);

-- ------------------------------------------------------------
-- rate limits
-- ------------------------------------------------------------
create table if not exists public.rate_limits (
  id uuid primary key default uuid_generate_v4(),
  identifier text not null,
  endpoint text not null,
  request_count integer not null default 1,
  window_start timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists idx_rate_limits_unique
  on public.rate_limits(identifier, endpoint, window_start);
create index if not exists idx_rate_limits_window_start
  on public.rate_limits(window_start);

alter table public.rate_limits enable row level security;

drop policy if exists "Service role full access" on public.rate_limits;
create policy "Service role full access" on public.rate_limits
  for all to service_role using (true) with check (true);

drop trigger if exists update_rate_limits_updated_at on public.rate_limits;
create trigger update_rate_limits_updated_at
  before update on public.rate_limits
  for each row execute function public.update_updated_at_column();

create or replace function public.cleanup_rate_limits(older_than_hours int default 24)
returns integer language plpgsql as $$
declare
  deleted_count integer;
begin
  delete from public.rate_limits
  where window_start < now() - (older_than_hours || ' hours')::interval;
  get diagnostics deleted_count = row_count;
  return deleted_count;
end;
$$;

create or replace function public.atomic_rate_limit_increment(
  p_identifier text,
  p_endpoint text,
  p_window_start timestamptz,
  p_max_requests integer
) returns table (request_count integer, is_limited boolean)
language plpgsql as $$
declare
  v_count integer;
begin
  insert into public.rate_limits (identifier, endpoint, request_count, window_start)
  values (p_identifier, p_endpoint, 1, p_window_start)
  on conflict (identifier, endpoint, window_start)
  do update set request_count = public.rate_limits.request_count + 1
  returning public.rate_limits.request_count into v_count;

  return query select v_count, v_count > p_max_requests;
end;
$$;

-- ------------------------------------------------------------
-- realtime for order tracking
-- ------------------------------------------------------------
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'orders'
  ) then
    alter publication supabase_realtime add table public.orders;
  end if;
end $$;

-- ------------------------------------------------------------
-- grant staff access
-- 1) Create the user first: Dashboard > Authentication > Users > Add user
--    (set a password and enable "Auto Confirm User").
-- 2) Replace REPLACE_WITH_STAFF_EMAIL below with that user's email.
-- 3) Run this statement (or the whole file again).
-- ------------------------------------------------------------
insert into public.staff (id, email, name, role)
select
  u.id,
  u.email,
  coalesce(u.raw_user_meta_data->>'name', split_part(u.email, '@', 1)),
  'admin'
from auth.users u
where lower(u.email) = lower('REPLACE_WITH_STAFF_EMAIL')
on conflict (id) do update
  set email = excluded.email,
      name = excluded.name,
      role = excluded.role;

-- Verify:
select id, email, role, created_at from public.staff;
