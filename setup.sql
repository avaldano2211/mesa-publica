-- ═══════════════════════════════════════════════════════════════════════════
-- MESA PÚBLICA · esquema completo — se pega UNA vez en Supabase → SQL Editor
--
-- ⚠️ ANTES DE EJECUTAR: reemplaza TU-CORREO@EJEMPLO.COM (línea final) por el
--    correo PERSONAL con el que te vas a registrar en la app (tú eres admin).
--
-- Seguridad: lista de invitados (amigos_permitidos). Cualquiera puede crear
-- login, pero sin estar en la lista NO VE NADA (RLS en todas las tablas).
-- El publicador (la mesa de Andrés) solo puede escribir mercado_actual.
-- Políticas simples a propósito: lección GES 2026-08-21 (RLS compleja = timeouts).
-- ═══════════════════════════════════════════════════════════════════════════

create table if not exists amigos_permitidos (
  email text primary key,
  es_admin boolean not null default false,
  agregado timestamptz not null default now()
);
alter table amigos_permitidos enable row level security;

create table if not exists perfiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  email text not null,
  nombre text,
  creado timestamptz not null default now()
);
alter table perfiles enable row level security;

create table if not exists planes (
  user_id uuid primary key references auth.users(id) on delete cascade,
  plan_pct int not null default 35 check (plan_pct between 1 and 200),
  ops_max int not null default 3 check (ops_max between 1 and 20),
  riesgo_pct int not null default 10 check (riesgo_pct between 1 and 100),
  capital numeric check (capital is null or capital >= 0)
);
alter table planes enable row level security;

create table if not exists operaciones (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  fecha date not null default current_date,
  ticker text not null,
  tipo text not null check (tipo in ('CALL','PUT')),
  strike numeric,
  expiracion date,
  contratos int not null default 1 check (contratos between 1 and 500),
  prima_entrada numeric not null check (prima_entrada > 0),
  prima_salida numeric check (prima_salida is null or prima_salida >= 0),
  estado text not null default 'abierta' check (estado in ('abierta','cerrada')),
  notas text,
  creado timestamptz not null default now()
);
create index if not exists operaciones_user_fecha on operaciones(user_id, fecha desc);
alter table operaciones enable row level security;

create table if not exists mercado_actual (
  id int primary key default 1 check (id = 1),
  ts timestamptz not null default now(),
  payload jsonb not null
);
alter table mercado_actual enable row level security;

-- helpers (security definer para que las políticas no re-evalúen RLS)
create or replace function es_permitido() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from amigos_permitidos a
                 where lower(a.email) = lower(coalesce(auth.email(), '')));
$$;

create or replace function es_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from amigos_permitidos a
                 where lower(a.email) = lower(coalesce(auth.email(), '')) and a.es_admin);
$$;

-- políticas
create policy amigos_sel on amigos_permitidos for select to authenticated using (es_permitido());
create policy amigos_ins on amigos_permitidos for insert to authenticated with check (es_admin());
create policy amigos_del on amigos_permitidos for delete to authenticated
  using (es_admin() and lower(email) <> lower(coalesce(auth.email(), '')));

create policy perfil_sel on perfiles for select to authenticated using (user_id = auth.uid());
create policy perfil_ins on perfiles for insert to authenticated
  with check (user_id = auth.uid() and es_permitido());
create policy perfil_upd on perfiles for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy plan_sel on planes for select to authenticated using (user_id = auth.uid());
create policy plan_ins on planes for insert to authenticated
  with check (user_id = auth.uid() and es_permitido());
create policy plan_upd on planes for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy op_sel on operaciones for select to authenticated using (user_id = auth.uid());
create policy op_ins on operaciones for insert to authenticated
  with check (user_id = auth.uid() and es_permitido());
create policy op_upd on operaciones for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy op_del on operaciones for delete to authenticated using (user_id = auth.uid());

create policy mercado_sel on mercado_actual for select to authenticated using (es_permitido());
create policy mercado_ins on mercado_actual for insert to authenticated
  with check (lower(coalesce(auth.email(), '')) = 'publicador@mesa-publica.local');
create policy mercado_upd on mercado_actual for update to authenticated
  using (lower(coalesce(auth.email(), '')) = 'publicador@mesa-publica.local')
  with check (lower(coalesce(auth.email(), '')) = 'publicador@mesa-publica.local');

-- semillas: el publicador (la mesa de Andrés) y TÚ como admin
insert into amigos_permitidos (email, es_admin) values
  ('publicador@mesa-publica.local', false),
  ('TU-CORREO@EJEMPLO.COM', true)
on conflict (email) do nothing;
