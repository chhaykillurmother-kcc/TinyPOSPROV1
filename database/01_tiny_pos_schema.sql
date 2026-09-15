-- ============================================================================
-- Tiny POS - Step 1: Supabase PostgreSQL foundation
-- Version: 1.0
-- Target: A NEW Supabase project
--
-- IMPORTANT:
-- 1. Run this file BEFORE creating your first Supabase Auth user.
-- 2. Run the whole file once in Supabase Dashboard > SQL Editor > New query.
-- 3. The first Auth user created after this script becomes the OWNER.
-- 4. Do not place the Supabase service-role key in frontend code.
-- ============================================================================

begin;

-- ----------------------------------------------------------------------------
-- 1. ENUM TYPES
-- ----------------------------------------------------------------------------

do $$
begin
  if not exists (select 1 from pg_type where typname = 'app_role') then
    create type public.app_role as enum ('owner', 'admin', 'manager', 'cashier', 'viewer');
  end if;

  if not exists (select 1 from pg_type where typname = 'currency_code') then
    create type public.currency_code as enum ('USD', 'KHR');
  end if;

  if not exists (select 1 from pg_type where typname = 'theme_mode') then
    create type public.theme_mode as enum ('system', 'light', 'dark');
  end if;

  if not exists (select 1 from pg_type where typname = 'discount_type') then
    create type public.discount_type as enum ('none', 'percent', 'fixed');
  end if;

  if not exists (select 1 from pg_type where typname = 'payment_method') then
    create type public.payment_method as enum ('cash', 'bank', 'khqr', 'card', 'other');
  end if;

  if not exists (select 1 from pg_type where typname = 'payment_status') then
    create type public.payment_status as enum ('unpaid', 'partial', 'paid', 'refunded');
  end if;

  if not exists (select 1 from pg_type where typname = 'sale_status') then
    create type public.sale_status as enum (
      'draft', 'parked', 'completed', 'partially_refunded', 'refunded', 'voided'
    );
  end if;

  if not exists (select 1 from pg_type where typname = 'purchase_status') then
    create type public.purchase_status as enum ('draft', 'ordered', 'received', 'cancelled');
  end if;

  if not exists (select 1 from pg_type where typname = 'return_status') then
    create type public.return_status as enum ('draft', 'completed', 'cancelled');
  end if;

  if not exists (select 1 from pg_type where typname = 'stock_movement_type') then
    create type public.stock_movement_type as enum (
      'opening',
      'sale',
      'sale_void',
      'purchase',
      'purchase_cancel',
      'customer_return',
      'supplier_return',
      'adjustment',
      'transfer_in',
      'transfer_out'
    );
  end if;

  if not exists (select 1 from pg_type where typname = 'adjustment_reason') then
    create type public.adjustment_reason as enum (
      'opening_stock',
      'count_correction',
      'damaged',
      'expired',
      'lost',
      'found',
      'internal_use',
      'other'
    );
  end if;
end
$$;

-- ----------------------------------------------------------------------------
-- 2. CORE BUSINESS AND USER TABLES
-- ----------------------------------------------------------------------------

create table if not exists public.organizations (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(trim(name)) between 1 and 120),
  code text not null unique check (code ~ '^[A-Z0-9_-]{2,30}$'),
  logo_url text,
  is_active boolean not null default true,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.branches (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  name text not null check (length(trim(name)) between 1 and 120),
  code text not null check (code ~ '^[A-Z0-9_-]{1,20}$'),
  phone text,
  address text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, code)
);

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  organization_id uuid not null references public.organizations(id) on delete cascade,
  branch_id uuid references public.branches(id) on delete set null,
  email text,
  full_name text not null default 'POS User',
  role public.app_role not null default 'cashier',
  phone text,
  avatar_url text,
  is_active boolean not null default true,
  last_login_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.user_preferences (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  language text not null default 'en' check (language in ('en', 'km')),
  theme public.theme_mode not null default 'system',
  accent_color text not null default '#2563eb'
    check (accent_color ~ '^#[0-9A-Fa-f]{6}$'),
  compact_mode boolean not null default false,
  sound_enabled boolean not null default true,
  scanner_vibration boolean not null default true,
  updated_at timestamptz not null default now()
);

create table if not exists public.app_settings (
  organization_id uuid primary key references public.organizations(id) on delete cascade,
  shop_name text not null default 'Tiny POS',
  shop_phone text,
  shop_address text,
  receipt_footer text default 'Thank you for your purchase.',
  default_language text not null default 'en' check (default_language in ('en', 'km')),
  default_theme public.theme_mode not null default 'system',
  base_currency public.currency_code not null default 'USD',
  usd_to_khr_rate numeric(14,4) not null default 4100 check (usd_to_khr_rate > 0),
  tax_percent numeric(7,4) not null default 0 check (tax_percent between 0 and 100),
  low_stock_threshold numeric(14,3) not null default 5 check (low_stock_threshold >= 0),
  allow_negative_stock boolean not null default false,
  receipt_width_mm integer not null default 80 check (receipt_width_mm in (58, 80)),
  invoice_prefix text not null default 'INV'
    check (invoice_prefix ~ '^[A-Z0-9_-]{1,12}$'),
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id) on delete set null
);

-- ----------------------------------------------------------------------------
-- 3. CATALOG, CUSTOMERS, SUPPLIERS, AND INVENTORY
-- ----------------------------------------------------------------------------

create table if not exists public.categories (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  name text not null check (length(trim(name)) between 1 and 100),
  description text,
  sort_order integer not null default 0,
  is_active boolean not null default true,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.suppliers (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  name text not null check (length(trim(name)) between 1 and 160),
  phone text,
  email text,
  address text,
  notes text,
  is_active boolean not null default true,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.customers (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  name text not null check (length(trim(name)) between 1 and 160),
  phone text,
  email text,
  address text,
  loyalty_points numeric(14,2) not null default 0 check (loyalty_points >= 0),
  credit_limit numeric(14,2) not null default 0 check (credit_limit >= 0),
  notes text,
  is_active boolean not null default true,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.products (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  category_id uuid references public.categories(id) on delete set null,
  name text not null check (length(trim(name)) between 1 and 200),
  name_km text,
  sku text,
  barcode text,
  description text,
  unit_name text not null default 'pcs',
  selling_price numeric(14,2) not null default 0 check (selling_price >= 0),
  default_cost numeric(14,4) not null default 0 check (default_cost >= 0),
  currency public.currency_code not null default 'USD',
  tax_percent numeric(7,4) not null default 0 check (tax_percent between 0 and 100),
  track_stock boolean not null default true,
  allow_negative_stock boolean not null default false,
  low_stock_threshold numeric(14,3) check (low_stock_threshold is null or low_stock_threshold >= 0),
  is_active boolean not null default true,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (barcode is null or length(trim(barcode)) > 0),
  check (sku is null or length(trim(sku)) > 0)
);

create table if not exists public.product_images (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete cascade,
  cloudinary_public_id text not null,
  secure_url text not null check (secure_url ~ '^https://'),
  width integer check (width is null or width > 0),
  height integer check (height is null or height > 0),
  sort_order integer not null default 0,
  is_primary boolean not null default false,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  unique (organization_id, cloudinary_public_id)
);

create table if not exists public.inventory_balances (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  branch_id uuid not null references public.branches(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete cascade,
  quantity numeric(14,3) not null default 0,
  average_cost numeric(14,4) not null default 0 check (average_cost >= 0),
  updated_at timestamptz not null default now(),
  unique (branch_id, product_id)
);

create table if not exists public.document_counters (
  organization_id uuid not null references public.organizations(id) on delete cascade,
  branch_id uuid not null references public.branches(id) on delete cascade,
  document_type text not null check (document_type ~ '^[A-Z0-9_-]{1,12}$'),
  counter_date date not null,
  last_number integer not null default 0 check (last_number >= 0),
  primary key (organization_id, branch_id, document_type, counter_date)
);

-- ----------------------------------------------------------------------------
-- 4. SALES AND PAYMENTS
-- ----------------------------------------------------------------------------

create table if not exists public.sales (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  branch_id uuid not null references public.branches(id) on delete restrict,
  invoice_number text not null,
  idempotency_key text,
  customer_id uuid references public.customers(id) on delete set null,
  cashier_id uuid not null references auth.users(id) on delete restrict,
  status public.sale_status not null default 'completed',
  payment_status public.payment_status not null default 'paid',
  currency public.currency_code not null default 'USD',
  subtotal numeric(14,2) not null default 0 check (subtotal >= 0),
  discount_type public.discount_type not null default 'none',
  discount_value numeric(14,4) not null default 0 check (discount_value >= 0),
  discount_amount numeric(14,2) not null default 0 check (discount_amount >= 0),
  tax_amount numeric(14,2) not null default 0 check (tax_amount >= 0),
  total_amount numeric(14,2) not null default 0 check (total_amount >= 0),
  paid_amount numeric(14,2) not null default 0 check (paid_amount >= 0),
  change_amount numeric(14,2) not null default 0 check (change_amount >= 0),
  cost_amount numeric(14,4) not null default 0 check (cost_amount >= 0),
  gross_profit numeric(14,4) not null default 0,
  notes text,
  completed_at timestamptz,
  voided_at timestamptz,
  voided_by uuid references auth.users(id) on delete set null,
  void_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, invoice_number)
);

create unique index if not exists sales_org_idempotency_key_uq
  on public.sales (organization_id, idempotency_key)
  where idempotency_key is not null;

create table if not exists public.sale_items (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  sale_id uuid not null references public.sales(id) on delete cascade,
  product_id uuid references public.products(id) on delete set null,
  product_name text not null,
  barcode text,
  quantity numeric(14,3) not null check (quantity > 0),
  unit_price numeric(14,2) not null check (unit_price >= 0),
  unit_cost numeric(14,4) not null check (unit_cost >= 0),
  discount_amount numeric(14,2) not null default 0 check (discount_amount >= 0),
  tax_amount numeric(14,2) not null default 0 check (tax_amount >= 0),
  line_total numeric(14,2) not null check (line_total >= 0),
  line_profit numeric(14,4) not null default 0,
  created_at timestamptz not null default now()
);

create table if not exists public.payments (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  branch_id uuid not null references public.branches(id) on delete restrict,
  sale_id uuid not null references public.sales(id) on delete cascade,
  method public.payment_method not null,
  currency public.currency_code not null,
  amount numeric(14,2) not null check (amount > 0),
  tendered_amount numeric(14,2) not null check (tendered_amount >= 0),
  change_amount numeric(14,2) not null default 0 check (change_amount >= 0),
  reference_number text,
  received_by uuid not null references auth.users(id) on delete restrict,
  paid_at timestamptz not null default now(),
  notes text
);

-- ----------------------------------------------------------------------------
-- 5. PURCHASES
-- ----------------------------------------------------------------------------

create table if not exists public.purchases (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  branch_id uuid not null references public.branches(id) on delete restrict,
  purchase_number text not null,
  supplier_id uuid references public.suppliers(id) on delete set null,
  status public.purchase_status not null default 'draft',
  currency public.currency_code not null default 'USD',
  subtotal numeric(14,2) not null default 0 check (subtotal >= 0),
  discount_amount numeric(14,2) not null default 0 check (discount_amount >= 0),
  tax_amount numeric(14,2) not null default 0 check (tax_amount >= 0),
  total_amount numeric(14,2) not null default 0 check (total_amount >= 0),
  amount_paid numeric(14,2) not null default 0 check (amount_paid >= 0),
  supplier_invoice_number text,
  notes text,
  ordered_at timestamptz,
  received_at timestamptz,
  created_by uuid not null references auth.users(id) on delete restrict,
  received_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, purchase_number)
);

create table if not exists public.purchase_items (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  purchase_id uuid not null references public.purchases(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete restrict,
  quantity numeric(14,3) not null check (quantity > 0),
  unit_cost numeric(14,4) not null check (unit_cost >= 0),
  tax_amount numeric(14,2) not null default 0 check (tax_amount >= 0),
  line_total numeric(14,2) not null check (line_total >= 0),
  created_at timestamptz not null default now()
);

-- ----------------------------------------------------------------------------
-- 6. RETURNS, INVENTORY ADJUSTMENTS, AND PARKED SALES
-- ----------------------------------------------------------------------------

create table if not exists public.returns (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  branch_id uuid not null references public.branches(id) on delete restrict,
  return_number text not null,
  original_sale_id uuid not null references public.sales(id) on delete restrict,
  customer_id uuid references public.customers(id) on delete set null,
  status public.return_status not null default 'completed',
  currency public.currency_code not null,
  refund_amount numeric(14,2) not null default 0 check (refund_amount >= 0),
  refund_method public.payment_method,
  reason text,
  processed_by uuid not null references auth.users(id) on delete restrict,
  processed_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  unique (organization_id, return_number)
);

create table if not exists public.return_items (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  return_id uuid not null references public.returns(id) on delete cascade,
  sale_item_id uuid not null references public.sale_items(id) on delete restrict,
  product_id uuid references public.products(id) on delete set null,
  quantity numeric(14,3) not null check (quantity > 0),
  unit_refund numeric(14,2) not null check (unit_refund >= 0),
  line_refund numeric(14,2) not null check (line_refund >= 0),
  restock boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.inventory_adjustments (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  branch_id uuid not null references public.branches(id) on delete restrict,
  adjustment_number text not null,
  reason public.adjustment_reason not null,
  notes text,
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  unique (organization_id, adjustment_number)
);

create table if not exists public.inventory_adjustment_items (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  adjustment_id uuid not null references public.inventory_adjustments(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete restrict,
  quantity_before numeric(14,3) not null,
  quantity_change numeric(14,3) not null check (quantity_change <> 0),
  quantity_after numeric(14,3) not null,
  unit_cost numeric(14,4) not null default 0 check (unit_cost >= 0),
  created_at timestamptz not null default now(),
  check (quantity_after = quantity_before + quantity_change)
);

create table if not exists public.parked_sales (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  branch_id uuid not null references public.branches(id) on delete cascade,
  parked_by uuid not null references auth.users(id) on delete cascade,
  label text,
  customer_id uuid references public.customers(id) on delete set null,
  currency public.currency_code not null default 'USD',
  cart jsonb not null default '[]'::jsonb check (jsonb_typeof(cart) = 'array'),
  discount_type public.discount_type not null default 'none',
  discount_value numeric(14,4) not null default 0 check (discount_value >= 0),
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ----------------------------------------------------------------------------
-- 7. STOCK MOVEMENT LEDGER AND AUDIT LOG
-- ----------------------------------------------------------------------------

create table if not exists public.stock_movements (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  branch_id uuid not null references public.branches(id) on delete restrict,
  product_id uuid not null references public.products(id) on delete restrict,
  movement_type public.stock_movement_type not null,
  quantity_change numeric(14,3) not null check (quantity_change <> 0),
  quantity_before numeric(14,3) not null,
  quantity_after numeric(14,3) not null,
  unit_cost numeric(14,4) not null default 0 check (unit_cost >= 0),
  reference_table text,
  reference_id uuid,
  notes text,
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  check (quantity_after = quantity_before + quantity_change)
);

create table if not exists public.audit_logs (
  id bigint generated always as identity primary key,
  organization_id uuid not null references public.organizations(id) on delete cascade,
  branch_id uuid references public.branches(id) on delete set null,
  user_id uuid references auth.users(id) on delete set null,
  action text not null,
  entity_type text not null,
  entity_id uuid,
  old_data jsonb,
  new_data jsonb,
  ip_address inet,
  user_agent text,
  created_at timestamptz not null default now()
);

-- ----------------------------------------------------------------------------
-- 8. INDEXES AND UNIQUENESS
-- ----------------------------------------------------------------------------

create unique index if not exists categories_org_name_uq
  on public.categories (organization_id, lower(name));

create unique index if not exists products_org_barcode_uq
  on public.products (organization_id, barcode)
  where barcode is not null;

create unique index if not exists products_org_sku_uq
  on public.products (organization_id, sku)
  where sku is not null;

create unique index if not exists product_images_one_primary_uq
  on public.product_images (product_id)
  where is_primary = true;

create unique index if not exists customers_org_phone_uq
  on public.customers (organization_id, phone)
  where phone is not null and length(trim(phone)) > 0;

create index if not exists profiles_organization_idx
  on public.profiles (organization_id);

create index if not exists profiles_branch_idx
  on public.profiles (branch_id);

create index if not exists products_org_active_idx
  on public.products (organization_id, is_active);

create index if not exists products_category_idx
  on public.products (category_id);

create index if not exists inventory_branch_product_idx
  on public.inventory_balances (branch_id, product_id);

create index if not exists sales_org_created_idx
  on public.sales (organization_id, created_at desc);

create index if not exists sales_branch_created_idx
  on public.sales (branch_id, created_at desc);

create index if not exists sales_cashier_created_idx
  on public.sales (cashier_id, created_at desc);

create index if not exists sale_items_sale_idx
  on public.sale_items (sale_id);

create index if not exists sale_items_product_idx
  on public.sale_items (product_id);

create index if not exists payments_sale_idx
  on public.payments (sale_id);

create index if not exists purchases_org_created_idx
  on public.purchases (organization_id, created_at desc);

create index if not exists stock_movements_product_created_idx
  on public.stock_movements (product_id, created_at desc);

create index if not exists stock_movements_branch_created_idx
  on public.stock_movements (branch_id, created_at desc);

create index if not exists audit_logs_org_created_idx
  on public.audit_logs (organization_id, created_at desc);

-- ----------------------------------------------------------------------------
-- 9. AUTOMATIC updated_at TRIGGER
-- ----------------------------------------------------------------------------

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'organizations',
    'branches',
    'profiles',
    'user_preferences',
    'app_settings',
    'categories',
    'suppliers',
    'customers',
    'products',
    'inventory_balances',
    'sales',
    'purchases',
    'parked_sales'
  ]
  loop
    execute format('drop trigger if exists set_%I_updated_at on public.%I', table_name, table_name);
    execute format(
      'create trigger set_%I_updated_at before update on public.%I
       for each row execute function public.set_updated_at()',
      table_name,
      table_name
    );
  end loop;
end
$$;

-- ----------------------------------------------------------------------------
-- 10. PRIVATE AUTHORIZATION HELPERS
-- These functions live in a non-exposed schema and are used by RLS policies.
-- ----------------------------------------------------------------------------

create schema if not exists private;

revoke all on schema private from public;
grant usage on schema private to authenticated, service_role;

create or replace function private.current_organization_id()
returns uuid
language sql
stable
security definer
set search_path = public, auth, pg_temp
as $$
  select p.organization_id
  from public.profiles p
  where p.id = (select auth.uid())
    and p.is_active = true
  limit 1
$$;

create or replace function private.current_branch_id()
returns uuid
language sql
stable
security definer
set search_path = public, auth, pg_temp
as $$
  select p.branch_id
  from public.profiles p
  where p.id = (select auth.uid())
    and p.is_active = true
  limit 1
$$;

create or replace function private.current_app_role()
returns public.app_role
language sql
stable
security definer
set search_path = public, auth, pg_temp
as $$
  select p.role
  from public.profiles p
  where p.id = (select auth.uid())
    and p.is_active = true
  limit 1
$$;

create or replace function private.is_active_user()
returns boolean
language sql
stable
security definer
set search_path = public, auth, pg_temp
as $$
  select exists (
    select 1
    from public.profiles p
    where p.id = (select auth.uid())
      and p.is_active = true
      and p.organization_id is not null
  )
$$;

create or replace function private.has_any_role(allowed_roles public.app_role[])
returns boolean
language sql
stable
security definer
set search_path = public, auth, pg_temp
as $$
  select coalesce(
    (select p.role = any(allowed_roles)
     from public.profiles p
     where p.id = (select auth.uid())
       and p.is_active = true),
    false
  )
$$;

revoke all on function private.current_organization_id() from public;
revoke all on function private.current_branch_id() from public;
revoke all on function private.current_app_role() from public;
revoke all on function private.is_active_user() from public;
revoke all on function private.has_any_role(public.app_role[]) from public;

grant execute on function private.current_organization_id() to authenticated, service_role;
grant execute on function private.current_branch_id() to authenticated, service_role;
grant execute on function private.current_app_role() to authenticated, service_role;
grant execute on function private.is_active_user() to authenticated, service_role;
grant execute on function private.has_any_role(public.app_role[]) to authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 11. DOCUMENT NUMBER GENERATOR
-- ----------------------------------------------------------------------------

create or replace function private.next_document_number(
  p_organization_id uuid,
  p_branch_id uuid,
  p_document_type text
)
returns text
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_number integer;
  v_branch_code text;
  v_doc_type text;
begin
  v_doc_type := upper(trim(p_document_type));

  if v_doc_type !~ '^[A-Z0-9_-]{1,12}$' then
    raise exception 'Invalid document type';
  end if;

  select b.code
  into v_branch_code
  from public.branches b
  where b.id = p_branch_id
    and b.organization_id = p_organization_id
    and b.is_active = true;

  if v_branch_code is null then
    raise exception 'Active branch not found';
  end if;

  insert into public.document_counters (
    organization_id,
    branch_id,
    document_type,
    counter_date,
    last_number
  )
  values (
    p_organization_id,
    p_branch_id,
    v_doc_type,
    current_date,
    1
  )
  on conflict (organization_id, branch_id, document_type, counter_date)
  do update
    set last_number = public.document_counters.last_number + 1
  returning last_number into v_number;

  return format(
    '%s-%s-%s-%s',
    v_doc_type,
    v_branch_code,
    to_char(current_date, 'YYYYMMDD'),
    lpad(v_number::text, 5, '0')
  );
end;
$$;

revoke all on function private.next_document_number(uuid, uuid, text) from public;
grant execute on function private.next_document_number(uuid, uuid, text)
  to authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 12. FIRST AUTH USER BOOTSTRAP
-- The first user becomes OWNER. Later users become CASHIER by default.
-- Keep public signup disabled after creating the owner. Add staff through an
-- admin-only backend function in a later step.
-- ----------------------------------------------------------------------------

create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
declare
  v_organization_id uuid;
  v_branch_id uuid;
  v_role public.app_role;
  v_name text;
begin
  -- Avoid two simultaneous "first user" signups.
  perform pg_advisory_xact_lock(hashtext('tiny_pos_first_auth_user'));

  select o.id
  into v_organization_id
  from public.organizations o
  order by o.created_at
  limit 1;

  if v_organization_id is null then
    insert into public.organizations (name, code, created_by)
    values (
      coalesce(nullif(trim(new.raw_user_meta_data ->> 'shop_name'), ''), 'Tiny POS'),
      'TINY_POS',
      new.id
    )
    returning id into v_organization_id;

    insert into public.branches (
      organization_id,
      name,
      code,
      is_active
    )
    values (
      v_organization_id,
      'Main Branch',
      'MAIN',
      true
    )
    returning id into v_branch_id;

    v_role := 'owner';

    insert into public.app_settings (
      organization_id,
      shop_name,
      updated_by
    )
    values (
      v_organization_id,
      coalesce(nullif(trim(new.raw_user_meta_data ->> 'shop_name'), ''), 'Tiny POS'),
      new.id
    )
    on conflict (organization_id) do nothing;

    insert into public.categories (
      organization_id,
      name,
      description,
      sort_order,
      created_by
    )
    values (
      v_organization_id,
      'General',
      'Default product category',
      0,
      new.id
    )
    on conflict do nothing;
  else
    select b.id
    into v_branch_id
    from public.branches b
    where b.organization_id = v_organization_id
      and b.is_active = true
    order by b.created_at
    limit 1;

    v_role := 'cashier';
  end if;

  v_name := coalesce(
    nullif(trim(new.raw_user_meta_data ->> 'full_name'), ''),
    nullif(split_part(coalesce(new.email, ''), '@', 1), ''),
    'POS User'
  );

  insert into public.profiles (
    id,
    organization_id,
    branch_id,
    email,
    full_name,
    role,
    is_active
  )
  values (
    new.id,
    v_organization_id,
    v_branch_id,
    new.email,
    v_name,
    v_role,
    true
  );

  insert into public.user_preferences (user_id)
  values (new.id)
  on conflict (user_id) do nothing;

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;

create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_auth_user();

revoke all on function public.handle_new_auth_user() from public, anon, authenticated;

-- ----------------------------------------------------------------------------
-- 13. SECURE CHECKOUT RPC
--
-- Frontend sends only product IDs and quantities:
-- [
--   {"product_id":"UUID","quantity":2},
--   {"product_id":"UUID","quantity":1}
-- ]
--
-- Product names, prices, costs, organization, branch, and stock are verified
-- inside PostgreSQL. All writes happen in one database transaction.
-- ----------------------------------------------------------------------------

create or replace function public.complete_sale(
  p_items jsonb,
  p_payment_method public.payment_method,
  p_amount_received numeric,
  p_customer_id uuid default null,
  p_discount_type public.discount_type default 'none',
  p_discount_value numeric default 0,
  p_tax_amount numeric default 0,
  p_currency public.currency_code default 'USD',
  p_notes text default null,
  p_payment_reference text default null,
  p_idempotency_key text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, private, auth, pg_temp
as $$
declare
  v_user_id uuid;
  v_profile record;
  v_item record;
  v_product record;
  v_balance record;
  v_sale_id uuid;
  v_existing_sale record;
  v_invoice_number text;
  v_subtotal numeric(14,2) := 0;
  v_discount_amount numeric(14,2) := 0;
  v_total numeric(14,2) := 0;
  v_change numeric(14,2) := 0;
  v_cost_total numeric(14,4) := 0;
  v_profit_total numeric(14,4) := 0;
  v_line_subtotal numeric(14,2);
  v_line_discount numeric(14,2);
  v_line_total numeric(14,2);
  v_line_cost numeric(14,4);
  v_allocated_discount numeric(14,2) := 0;
  v_item_count integer := 0;
  v_item_index integer := 0;
  v_setting_allow_negative boolean := false;
begin
  v_user_id := auth.uid();

  if v_user_id is null then
    raise exception 'Authentication required';
  end if;

  select
    p.organization_id,
    p.branch_id,
    p.role,
    p.is_active
  into v_profile
  from public.profiles p
  where p.id = v_user_id;

  if not found or v_profile.is_active is not true then
    raise exception 'Your POS user account is inactive or missing';
  end if;

  if v_profile.branch_id is null then
    raise exception 'No branch is assigned to this user';
  end if;

  if v_profile.role not in ('owner', 'admin', 'manager', 'cashier') then
    raise exception 'Your role cannot complete sales';
  end if;

  if p_items is null
     or jsonb_typeof(p_items) <> 'array'
     or jsonb_array_length(p_items) = 0 then
    raise exception 'The cart is empty';
  end if;

  if p_amount_received is null or p_amount_received < 0 then
    raise exception 'Invalid received amount';
  end if;

  if p_discount_value is null or p_discount_value < 0 then
    raise exception 'Invalid discount value';
  end if;

  if p_tax_amount is null or p_tax_amount < 0 then
    raise exception 'Invalid tax amount';
  end if;

  if p_idempotency_key is not null and length(trim(p_idempotency_key)) > 0 then
    select s.id, s.invoice_number, s.total_amount, s.change_amount
    into v_existing_sale
    from public.sales s
    where s.organization_id = v_profile.organization_id
      and s.idempotency_key = trim(p_idempotency_key)
    limit 1;

    if found then
      return jsonb_build_object(
        'ok', true,
        'duplicate_request', true,
        'sale_id', v_existing_sale.id,
        'invoice_number', v_existing_sale.invoice_number,
        'total_amount', v_existing_sale.total_amount,
        'change_amount', v_existing_sale.change_amount
      );
    end if;
  end if;

  if p_customer_id is not null and not exists (
    select 1
    from public.customers c
    where c.id = p_customer_id
      and c.organization_id = v_profile.organization_id
      and c.is_active = true
  ) then
    raise exception 'Customer not found';
  end if;

  select coalesce(s.allow_negative_stock, false)
  into v_setting_allow_negative
  from public.app_settings s
  where s.organization_id = v_profile.organization_id;

  -- Merge duplicate products and lock rows in a stable order.
  select count(*)
  into v_item_count
  from (
    select x.product_id
    from jsonb_to_recordset(p_items)
      as x(product_id uuid, quantity numeric)
    group by x.product_id
  ) q;

  if v_item_count = 0 then
    raise exception 'The cart contains no valid items';
  end if;

  for v_item in
    select
      x.product_id,
      sum(x.quantity)::numeric(14,3) as quantity
    from jsonb_to_recordset(p_items)
      as x(product_id uuid, quantity numeric)
    group by x.product_id
    order by x.product_id
  loop
    if v_item.product_id is null
       or v_item.quantity is null
       or v_item.quantity <= 0 then
      raise exception 'Every cart item requires a product and quantity greater than zero';
    end if;

    select
      p.id,
      p.name,
      p.barcode,
      p.selling_price,
      p.default_cost,
      p.currency,
      p.track_stock,
      p.allow_negative_stock,
      p.is_active
    into v_product
    from public.products p
    where p.id = v_item.product_id
      and p.organization_id = v_profile.organization_id
    for share;

    if not found or v_product.is_active is not true then
      raise exception 'Product % is missing or inactive', v_item.product_id;
    end if;

    if v_product.currency <> p_currency then
      raise exception 'Product "%" uses %, but this sale uses %',
        v_product.name, v_product.currency, p_currency;
    end if;

    insert into public.inventory_balances (
      organization_id,
      branch_id,
      product_id,
      quantity,
      average_cost
    )
    values (
      v_profile.organization_id,
      v_profile.branch_id,
      v_product.id,
      0,
      v_product.default_cost
    )
    on conflict (branch_id, product_id) do nothing;

    select
      ib.id,
      ib.quantity,
      ib.average_cost
    into v_balance
    from public.inventory_balances ib
    where ib.branch_id = v_profile.branch_id
      and ib.product_id = v_product.id
    for update;

    if v_product.track_stock
       and not (v_setting_allow_negative or v_product.allow_negative_stock)
       and v_balance.quantity < v_item.quantity then
      raise exception 'Not enough stock for "%". Available: %, requested: %',
        v_product.name, v_balance.quantity, v_item.quantity;
    end if;

    v_line_subtotal := round(v_product.selling_price * v_item.quantity, 2);
    v_subtotal := v_subtotal + v_line_subtotal;
  end loop;

  if p_discount_type = 'percent' then
    if p_discount_value > 100 then
      raise exception 'Percentage discount cannot exceed 100';
    end if;
    v_discount_amount := round(v_subtotal * p_discount_value / 100, 2);
  elsif p_discount_type = 'fixed' then
    v_discount_amount := least(round(p_discount_value, 2), v_subtotal);
  else
    v_discount_amount := 0;
  end if;

  v_total := greatest(round(v_subtotal - v_discount_amount + p_tax_amount, 2), 0);

  if p_amount_received < v_total then
    raise exception 'Received amount (%) is less than total (%)',
      p_amount_received, v_total;
  end if;

  if p_payment_method = 'cash' then
    v_change := round(p_amount_received - v_total, 2);
  else
    v_change := 0;
  end if;

  v_invoice_number := private.next_document_number(
    v_profile.organization_id,
    v_profile.branch_id,
    'INV'
  );

  insert into public.sales (
    organization_id,
    branch_id,
    invoice_number,
    idempotency_key,
    customer_id,
    cashier_id,
    status,
    payment_status,
    currency,
    subtotal,
    discount_type,
    discount_value,
    discount_amount,
    tax_amount,
    total_amount,
    paid_amount,
    change_amount,
    cost_amount,
    gross_profit,
    notes,
    completed_at
  )
  values (
    v_profile.organization_id,
    v_profile.branch_id,
    v_invoice_number,
    nullif(trim(p_idempotency_key), ''),
    p_customer_id,
    v_user_id,
    'completed',
    'paid',
    p_currency,
    v_subtotal,
    p_discount_type,
    p_discount_value,
    v_discount_amount,
    round(p_tax_amount, 2),
    v_total,
    v_total,
    v_change,
    0,
    0,
    nullif(trim(p_notes), ''),
    now()
  )
  returning id into v_sale_id;

  -- Insert item snapshots, deduct inventory, and write the stock ledger.
  for v_item in
    select
      x.product_id,
      sum(x.quantity)::numeric(14,3) as quantity
    from jsonb_to_recordset(p_items)
      as x(product_id uuid, quantity numeric)
    group by x.product_id
    order by x.product_id
  loop
    v_item_index := v_item_index + 1;

    select
      p.id,
      p.name,
      p.barcode,
      p.selling_price,
      p.default_cost,
      p.track_stock
    into strict v_product
    from public.products p
    where p.id = v_item.product_id
      and p.organization_id = v_profile.organization_id;

    select
      ib.quantity,
      ib.average_cost
    into strict v_balance
    from public.inventory_balances ib
    where ib.branch_id = v_profile.branch_id
      and ib.product_id = v_product.id
    for update;

    v_line_subtotal := round(v_product.selling_price * v_item.quantity, 2);

    if v_item_index = v_item_count then
      v_line_discount := v_discount_amount - v_allocated_discount;
    elsif v_subtotal > 0 then
      v_line_discount := round(
        v_discount_amount * v_line_subtotal / v_subtotal,
        2
      );
      v_allocated_discount := v_allocated_discount + v_line_discount;
    else
      v_line_discount := 0;
    end if;

    v_line_total := greatest(v_line_subtotal - v_line_discount, 0);
    v_line_cost := round(
      coalesce(nullif(v_balance.average_cost, 0), v_product.default_cost)
      * v_item.quantity,
      4
    );

    insert into public.sale_items (
      organization_id,
      sale_id,
      product_id,
      product_name,
      barcode,
      quantity,
      unit_price,
      unit_cost,
      discount_amount,
      tax_amount,
      line_total,
      line_profit
    )
    values (
      v_profile.organization_id,
      v_sale_id,
      v_product.id,
      v_product.name,
      v_product.barcode,
      v_item.quantity,
      v_product.selling_price,
      coalesce(nullif(v_balance.average_cost, 0), v_product.default_cost),
      v_line_discount,
      0,
      v_line_total,
      round(v_line_total - v_line_cost, 4)
    );

    v_cost_total := v_cost_total + v_line_cost;
    v_profit_total := v_profit_total + round(v_line_total - v_line_cost, 4);

    if v_product.track_stock then
      update public.inventory_balances
      set quantity = quantity - v_item.quantity,
          updated_at = now()
      where branch_id = v_profile.branch_id
        and product_id = v_product.id;

      insert into public.stock_movements (
        organization_id,
        branch_id,
        product_id,
        movement_type,
        quantity_change,
        quantity_before,
        quantity_after,
        unit_cost,
        reference_table,
        reference_id,
        notes,
        created_by
      )
      values (
        v_profile.organization_id,
        v_profile.branch_id,
        v_product.id,
        'sale',
        -v_item.quantity,
        v_balance.quantity,
        v_balance.quantity - v_item.quantity,
        coalesce(nullif(v_balance.average_cost, 0), v_product.default_cost),
        'sales',
        v_sale_id,
        v_invoice_number,
        v_user_id
      );
    end if;
  end loop;

  update public.sales
  set cost_amount = v_cost_total,
      gross_profit = v_profit_total
  where id = v_sale_id;

  if v_total > 0 then
    insert into public.payments (
      organization_id,
      branch_id,
      sale_id,
      method,
      currency,
      amount,
      tendered_amount,
      change_amount,
      reference_number,
      received_by
    )
    values (
      v_profile.organization_id,
      v_profile.branch_id,
      v_sale_id,
      p_payment_method,
      p_currency,
      v_total,
      p_amount_received,
      v_change,
      nullif(trim(p_payment_reference), ''),
      v_user_id
    );
  end if;

  insert into public.audit_logs (
    organization_id,
    branch_id,
    user_id,
    action,
    entity_type,
    entity_id,
    new_data
  )
  values (
    v_profile.organization_id,
    v_profile.branch_id,
    v_user_id,
    'complete_sale',
    'sale',
    v_sale_id,
    jsonb_build_object(
      'invoice_number', v_invoice_number,
      'subtotal', v_subtotal,
      'discount_amount', v_discount_amount,
      'tax_amount', p_tax_amount,
      'total_amount', v_total,
      'cost_amount', v_cost_total,
      'gross_profit', v_profit_total
    )
  );

  return jsonb_build_object(
    'ok', true,
    'duplicate_request', false,
    'sale_id', v_sale_id,
    'invoice_number', v_invoice_number,
    'subtotal', v_subtotal,
    'discount_amount', v_discount_amount,
    'tax_amount', round(p_tax_amount, 2),
    'total_amount', v_total,
    'amount_received', p_amount_received,
    'change_amount', v_change,
    'cost_amount', v_cost_total,
    'gross_profit', v_profit_total
  );

exception
  when unique_violation then
    if p_idempotency_key is not null then
      select s.id, s.invoice_number, s.total_amount, s.change_amount
      into v_existing_sale
      from public.sales s
      where s.organization_id = v_profile.organization_id
        and s.idempotency_key = trim(p_idempotency_key)
      limit 1;

      if found then
        return jsonb_build_object(
          'ok', true,
          'duplicate_request', true,
          'sale_id', v_existing_sale.id,
          'invoice_number', v_existing_sale.invoice_number,
          'total_amount', v_existing_sale.total_amount,
          'change_amount', v_existing_sale.change_amount
        );
      end if;
    end if;
    raise;
end;
$$;

revoke all on function public.complete_sale(
  jsonb,
  public.payment_method,
  numeric,
  uuid,
  public.discount_type,
  numeric,
  numeric,
  public.currency_code,
  text,
  text,
  text
) from public, anon;

grant execute on function public.complete_sale(
  jsonb,
  public.payment_method,
  numeric,
  uuid,
  public.discount_type,
  numeric,
  numeric,
  public.currency_code,
  text,
  text,
  text
) to authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 14. ROW LEVEL SECURITY
-- ----------------------------------------------------------------------------

alter table public.organizations enable row level security;
alter table public.branches enable row level security;
alter table public.profiles enable row level security;
alter table public.user_preferences enable row level security;
alter table public.app_settings enable row level security;
alter table public.categories enable row level security;
alter table public.suppliers enable row level security;
alter table public.customers enable row level security;
alter table public.products enable row level security;
alter table public.product_images enable row level security;
alter table public.inventory_balances enable row level security;
alter table public.document_counters enable row level security;
alter table public.sales enable row level security;
alter table public.sale_items enable row level security;
alter table public.payments enable row level security;
alter table public.purchases enable row level security;
alter table public.purchase_items enable row level security;
alter table public.returns enable row level security;
alter table public.return_items enable row level security;
alter table public.inventory_adjustments enable row level security;
alter table public.inventory_adjustment_items enable row level security;
alter table public.parked_sales enable row level security;
alter table public.stock_movements enable row level security;
alter table public.audit_logs enable row level security;

-- Remove old policies if this script is rerun.
do $$
declare
  r record;
begin
  for r in
    select schemaname, tablename, policyname
    from pg_policies
    where schemaname = 'public'
      and tablename in (
        'organizations', 'branches', 'profiles', 'user_preferences',
        'app_settings', 'categories', 'suppliers', 'customers', 'products',
        'product_images', 'inventory_balances', 'document_counters',
        'sales', 'sale_items', 'payments', 'purchases', 'purchase_items',
        'returns', 'return_items', 'inventory_adjustments',
        'inventory_adjustment_items', 'parked_sales', 'stock_movements',
        'audit_logs'
      )
  loop
    execute format(
      'drop policy if exists %I on %I.%I',
      r.policyname,
      r.schemaname,
      r.tablename
    );
  end loop;
end
$$;

-- Organization and branch visibility.
create policy organizations_select_own
on public.organizations
for select to authenticated
using (
  id = (select private.current_organization_id())
);

create policy organizations_update_owner
on public.organizations
for update to authenticated
using (
  id = (select private.current_organization_id())
  and (select private.has_any_role(array['owner']::public.app_role[]))
)
with check (
  id = (select private.current_organization_id())
  and (select private.has_any_role(array['owner']::public.app_role[]))
);

create policy branches_select_own_org
on public.branches
for select to authenticated
using (
  organization_id = (select private.current_organization_id())
);

create policy branches_manage_admins
on public.branches
for all to authenticated
using (
  organization_id = (select private.current_organization_id())
  and (select private.has_any_role(array['owner','admin']::public.app_role[]))
)
with check (
  organization_id = (select private.current_organization_id())
  and (select private.has_any_role(array['owner','admin']::public.app_role[]))
);

-- Profiles are visible inside the business, but direct profile changes are
-- intentionally blocked. User/role changes will use a server-side admin API.
create policy profiles_select_own_org
on public.profiles
for select to authenticated
using (
  organization_id = (select private.current_organization_id())
);

-- Every user controls only their own visual preferences.
create policy preferences_select_own
on public.user_preferences
for select to authenticated
using (
  user_id = (select auth.uid())
);

create policy preferences_insert_own
on public.user_preferences
for insert to authenticated
with check (
  user_id = (select auth.uid())
);

create policy preferences_update_own
on public.user_preferences
for update to authenticated
using (
  user_id = (select auth.uid())
)
with check (
  user_id = (select auth.uid())
);

-- Shop-wide settings.
create policy app_settings_select_own_org
on public.app_settings
for select to authenticated
using (
  organization_id = (select private.current_organization_id())
);

create policy app_settings_update_admins
on public.app_settings
for update to authenticated
using (
  organization_id = (select private.current_organization_id())
  and (select private.has_any_role(array['owner','admin']::public.app_role[]))
)
with check (
  organization_id = (select private.current_organization_id())
  and (select private.has_any_role(array['owner','admin']::public.app_role[]))
);

-- Catalog.
create policy categories_select_active_user
on public.categories
for select to authenticated
using (
  organization_id = (select private.current_organization_id())
);

create policy categories_manage_management
on public.categories
for all to authenticated
using (
  organization_id = (select private.current_organization_id())
  and (select private.has_any_role(array['owner','admin','manager']::public.app_role[]))
)
with check (
  organization_id = (select private.current_organization_id())
  and (select private.has_any_role(array['owner','admin','manager']::public.app_role[]))
);

create policy products_select_active_user
on public.products
for select to authenticated
using (
  organization_id = (select private.current_organization_id())
);

create policy products_manage_management
on public.products
for all to authenticated
using (
  organization_id = (select private.current_organization_id())
  and (select private.has_any_role(array['owner','admin','manager']::public.app_role[]))
)
with check (
  organization_id = (select private.current_organization_id())
  and (select private.has_any_role(array['owner','admin','manager']::public.app_role[]))
);

create policy product_images_select_active_user
on public.product_images
for select to authenticated
using (
  organization_id = (select private.current_organization_id())
);

create policy product_images_manage_management
on public.product_images
for all to authenticated
using (
  organization_id = (select private.current_organization_id())
  and (select private.has_any_role(array['owner','admin','manager']::public.app_role[]))
)
with check (
  organization_id = (select private.current_organization_id())
  and (select private.has_any_role(array['owner','admin','manager']::public.app_role[]))
);

-- Customers: cashiers may create/update customers, but only management may
-- delete them.
create policy customers_select_active_user
on public.customers
for select to authenticated
using (
  organization_id = (select private.current_organization_id())
);

create policy customers_insert_staff
on public.customers
for insert to authenticated
with check (
  organization_id = (select private.current_organization_id())
  and (select private.has_any_role(array['owner','admin','manager','cashier']::public.app_role[]))
);

create policy customers_update_staff
on public.customers
for update to authenticated
using (
  organization_id = (select private.current_organization_id())
  and (select private.has_any_role(array['owner','admin','manager','cashier']::public.app_role[]))
)
with check (
  organization_id = (select private.current_organization_id())
  and (select private.has_any_role(array['owner','admin','manager','cashier']::public.app_role[]))
);

create policy customers_delete_management
on public.customers
for delete to authenticated
using (
  organization_id = (select private.current_organization_id())
  and (select private.has_any_role(array['owner','admin','manager']::public.app_role[]))
);

-- Suppliers.
create policy suppliers_select_management
on public.suppliers
for select to authenticated
using (
  organization_id = (select private.current_organization_id())
  and (select private.has_any_role(array['owner','admin','manager']::public.app_role[]))
);

create policy suppliers_manage_management
on public.suppliers
for all to authenticated
using (
  organization_id = (select private.current_organization_id())
  and (select private.has_any_role(array['owner','admin','manager']::public.app_role[]))
)
with check (
  organization_id = (select private.current_organization_id())
  and (select private.has_any_role(array['owner','admin','manager']::public.app_role[]))
);

-- Inventory balances are readable by staff. Direct changes are blocked;
-- stock-changing operations must use secure database/backend functions.
create policy inventory_select_active_user
on public.inventory_balances
for select to authenticated
using (
  organization_id = (select private.current_organization_id())
);

-- Sales: management sees all organization sales; a cashier sees their own.
create policy sales_select_authorized
on public.sales
for select to authenticated
using (
  organization_id = (select private.current_organization_id())
  and (
    cashier_id = (select auth.uid())
    or (select private.has_any_role(array['owner','admin','manager','viewer']::public.app_role[]))
  )
);

create policy sale_items_select_authorized
on public.sale_items
for select to authenticated
using (
  organization_id = (select private.current_organization_id())
  and exists (
    select 1
    from public.sales s
    where s.id = sale_items.sale_id
      and s.organization_id = (select private.current_organization_id())
      and (
        s.cashier_id = (select auth.uid())
        or (select private.has_any_role(array['owner','admin','manager','viewer']::public.app_role[]))
      )
  )
);

create policy payments_select_authorized
on public.payments
for select to authenticated
using (
  organization_id = (select private.current_organization_id())
  and exists (
    select 1
    from public.sales s
    where s.id = payments.sale_id
      and s.organization_id = (select private.current_organization_id())
      and (
        s.cashier_id = (select auth.uid())
        or (select private.has_any_role(array['owner','admin','manager','viewer']::public.app_role[]))
      )
  )
);

-- Purchasing and return records are management-only. Direct stock-changing
-- writes are intentionally blocked until their secure RPC functions are added.
create policy purchases_select_management
on public.purchases
for select to authenticated
using (
  organization_id = (select private.current_organization_id())
  and (select private.has_any_role(array['owner','admin','manager']::public.app_role[]))
);

create policy purchase_items_select_management
on public.purchase_items
for select to authenticated
using (
  organization_id = (select private.current_organization_id())
  and (select private.has_any_role(array['owner','admin','manager']::public.app_role[]))
);

create policy returns_select_management
on public.returns
for select to authenticated
using (
  organization_id = (select private.current_organization_id())
  and (select private.has_any_role(array['owner','admin','manager']::public.app_role[]))
);

create policy return_items_select_management
on public.return_items
for select to authenticated
using (
  organization_id = (select private.current_organization_id())
  and (select private.has_any_role(array['owner','admin','manager']::public.app_role[]))
);

create policy adjustments_select_management
on public.inventory_adjustments
for select to authenticated
using (
  organization_id = (select private.current_organization_id())
  and (select private.has_any_role(array['owner','admin','manager']::public.app_role[]))
);

create policy adjustment_items_select_management
on public.inventory_adjustment_items
for select to authenticated
using (
  organization_id = (select private.current_organization_id())
  and (select private.has_any_role(array['owner','admin','manager']::public.app_role[]))
);

-- Parked sales belong to their cashier; management may access all.
create policy parked_sales_select_authorized
on public.parked_sales
for select to authenticated
using (
  organization_id = (select private.current_organization_id())
  and (
    parked_by = (select auth.uid())
    or (select private.has_any_role(array['owner','admin','manager']::public.app_role[]))
  )
);

create policy parked_sales_insert_staff
on public.parked_sales
for insert to authenticated
with check (
  organization_id = (select private.current_organization_id())
  and branch_id = (select private.current_branch_id())
  and parked_by = (select auth.uid())
  and (select private.has_any_role(array['owner','admin','manager','cashier']::public.app_role[]))
);

create policy parked_sales_update_authorized
on public.parked_sales
for update to authenticated
using (
  organization_id = (select private.current_organization_id())
  and (
    parked_by = (select auth.uid())
    or (select private.has_any_role(array['owner','admin','manager']::public.app_role[]))
  )
)
with check (
  organization_id = (select private.current_organization_id())
  and (
    parked_by = (select auth.uid())
    or (select private.has_any_role(array['owner','admin','manager']::public.app_role[]))
  )
);

create policy parked_sales_delete_authorized
on public.parked_sales
for delete to authenticated
using (
  organization_id = (select private.current_organization_id())
  and (
    parked_by = (select auth.uid())
    or (select private.has_any_role(array['owner','admin','manager']::public.app_role[]))
  )
);

-- Stock movement history and audit history.
create policy stock_movements_select_active_user
on public.stock_movements
for select to authenticated
using (
  organization_id = (select private.current_organization_id())
);

create policy audit_logs_select_management
on public.audit_logs
for select to authenticated
using (
  organization_id = (select private.current_organization_id())
  and (select private.has_any_role(array['owner','admin','manager']::public.app_role[]))
);

-- Document counters have no direct client policy.

-- ----------------------------------------------------------------------------
-- 15. API PRIVILEGES
-- RLS still decides which rows an authenticated user can access.
-- ----------------------------------------------------------------------------

revoke all on all tables in schema public from anon;

grant select, insert, update, delete on
  public.organizations,
  public.branches,
  public.profiles,
  public.user_preferences,
  public.app_settings,
  public.categories,
  public.suppliers,
  public.customers,
  public.products,
  public.product_images,
  public.inventory_balances,
  public.document_counters,
  public.sales,
  public.sale_items,
  public.payments,
  public.purchases,
  public.purchase_items,
  public.returns,
  public.return_items,
  public.inventory_adjustments,
  public.inventory_adjustment_items,
  public.parked_sales,
  public.stock_movements,
  public.audit_logs
to authenticated;

grant all on
  public.organizations,
  public.branches,
  public.profiles,
  public.user_preferences,
  public.app_settings,
  public.categories,
  public.suppliers,
  public.customers,
  public.products,
  public.product_images,
  public.inventory_balances,
  public.document_counters,
  public.sales,
  public.sale_items,
  public.payments,
  public.purchases,
  public.purchase_items,
  public.returns,
  public.return_items,
  public.inventory_adjustments,
  public.inventory_adjustment_items,
  public.parked_sales,
  public.stock_movements,
  public.audit_logs
to service_role;

grant usage, select on all sequences in schema public to service_role;
grant usage, select on all sequences in schema public to authenticated;

-- ----------------------------------------------------------------------------
-- 16. PRODUCT CATALOG VIEW
-- This view obeys RLS on the underlying tables.
-- ----------------------------------------------------------------------------

create or replace view public.product_catalog
with (security_invoker = true)
as
select
  p.id,
  p.organization_id,
  ib.branch_id,
  p.category_id,
  c.name as category_name,
  p.name,
  p.name_km,
  p.sku,
  p.barcode,
  p.description,
  p.unit_name,
  p.selling_price,
  p.default_cost,
  p.currency,
  p.tax_percent,
  p.track_stock,
  p.allow_negative_stock,
  coalesce(
    p.low_stock_threshold,
    s.low_stock_threshold,
    0
  ) as low_stock_threshold,
  coalesce(ib.quantity, 0) as stock_quantity,
  coalesce(ib.average_cost, p.default_cost, 0) as average_cost,
  pi.secure_url as image_url,
  pi.cloudinary_public_id,
  p.is_active,
  p.created_at,
  p.updated_at
from public.products p
left join public.categories c
  on c.id = p.category_id
left join public.inventory_balances ib
  on ib.product_id = p.id
left join public.app_settings s
  on s.organization_id = p.organization_id
left join lateral (
  select
    x.secure_url,
    x.cloudinary_public_id
  from public.product_images x
  where x.product_id = p.id
  order by x.is_primary desc, x.sort_order asc, x.created_at asc
  limit 1
) pi on true;

revoke all on public.product_catalog from anon;
grant select on public.product_catalog to authenticated, service_role;

commit;

-- ============================================================================
-- END OF STEP 1
-- ============================================================================
