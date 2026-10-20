-- =====================================================================
-- Weld Path — Join Codes setup (v2, 2026-10-20)
-- Run this ONCE in: Supabase Dashboard → SQL Editor → New query → Run
-- It adds class join codes: the teacher makes a code in the app
-- (Admin → Join codes), students enter it on their Dashboard,
-- and the teacher sees the class list. Safe to run more than once.
-- =====================================================================

create table if not exists public.join_codes (
  code         text primary key,
  level_number int  not null,
  label        text not null default '',
  created_by   uuid,
  is_active    boolean not null default true,
  created_at   timestamptz not null default now()
);

create table if not exists public.join_redemptions (
  id         uuid primary key default gen_random_uuid(),
  code       text not null references public.join_codes(code) on delete cascade,
  student_id uuid not null,
  created_at timestamptz not null default now(),
  unique (code, student_id)
);

alter table public.join_codes       enable row level security;
alter table public.join_redemptions enable row level security;
-- No public policies: the tables are only touched by the functions
-- below (security definer), after they check who is asking.

-- Teacher: make a new code -------------------------------------------
create or replace function public.create_join_code(p_level int, p_label text)
returns text
language plpgsql security definer set search_path = public
as $$
declare v_code text;
begin
  if not exists (select 1 from public.profiles where id = auth.uid() and role = 'admin') then
    raise exception 'admins only';
  end if;
  loop
    v_code := 'WELD-' || (1000 + floor(random() * 9000))::int::text;
    exit when not exists (select 1 from public.join_codes where code = v_code);
  end loop;
  insert into public.join_codes(code, level_number, label, created_by)
  values (v_code, p_level, coalesce(p_label, ''), auth.uid());
  return v_code;
end $$;

-- Student: join with a code -------------------------------------------
create or replace function public.redeem_join_code(p_code text)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare v_row public.join_codes;
begin
  if auth.uid() is null then
    return jsonb_build_object('status', 'invalid');
  end if;
  select * into v_row from public.join_codes
   where code = upper(trim(p_code)) and is_active;
  if not found then
    return jsonb_build_object('status', 'invalid');
  end if;
  if exists (select 1 from public.join_redemptions
              where code = v_row.code and student_id = auth.uid()) then
    return jsonb_build_object('status', 'already',
                              'label', v_row.label,
                              'level_number', v_row.level_number);
  end if;
  insert into public.join_redemptions(code, student_id)
  values (v_row.code, auth.uid());
  return jsonb_build_object('status', 'joined',
                            'label', v_row.label,
                            'level_number', v_row.level_number);
end $$;

-- Teacher: list all codes with join counts ----------------------------
create or replace function public.admin_join_codes()
returns table(code text, label text, level_number int,
              is_active boolean, created_at timestamptz, joined_count bigint)
language plpgsql security definer set search_path = public
as $$
begin
  if not exists (select 1 from public.profiles where id = auth.uid() and role = 'admin') then
    raise exception 'admins only';
  end if;
  return query
    select j.code, j.label, j.level_number, j.is_active, j.created_at,
           count(r.id)
      from public.join_codes j
      left join public.join_redemptions r on r.code = j.code
     group by j.code
     order by j.created_at desc;
end $$;

-- Teacher: who joined with one code -----------------------------------
create or replace function public.admin_code_students(p_code text)
returns table(full_name text, phone text, joined_at timestamptz)
language plpgsql security definer set search_path = public
as $$
begin
  if not exists (select 1 from public.profiles where id = auth.uid() and role = 'admin') then
    raise exception 'admins only';
  end if;
  return query
    select p.full_name, p.phone, r.created_at
      from public.join_redemptions r
      join public.profiles p on p.id = r.student_id
     where r.code = upper(trim(p_code))
     order by r.created_at;
end $$;

-- Only logged-in users may call these ----------------------------------
revoke execute on function public.create_join_code(int, text)      from public, anon;
revoke execute on function public.redeem_join_code(text)           from public, anon;
revoke execute on function public.admin_join_codes()               from public, anon;
revoke execute on function public.admin_code_students(text)        from public, anon;
grant  execute on function public.create_join_code(int, text) to authenticated;
grant  execute on function public.redeem_join_code(text)      to authenticated;
grant  execute on function public.admin_join_codes()           to authenticated;
grant  execute on function public.admin_code_students(text)    to authenticated;
