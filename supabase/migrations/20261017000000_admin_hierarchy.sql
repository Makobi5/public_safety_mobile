begin;

alter table public.police_stations
  add column if not exists station_type text not null default 'station',
  add column if not exists parent_station_id uuid
    references public.police_stations(id) on delete restrict;

alter table public.police_stations
  drop constraint if exists police_stations_station_type_check;

alter table public.police_stations
  add constraint police_stations_station_type_check
  check (station_type in ('cps', 'station', 'post'));

create index if not exists police_stations_parent_station_id_idx
  on public.police_stations(parent_station_id);

alter table public.user_profiles
  add column if not exists assigned_station_id uuid
    references public.police_stations(id) on delete restrict,
  add column if not exists account_status text not null default 'active';

alter table public.user_profiles
  drop constraint if exists user_profiles_account_status_check;

alter table public.user_profiles
  add constraint user_profiles_account_status_check
  check (account_status in ('active', 'suspended'));

alter table public.user_profiles
  drop constraint if exists user_profiles_role_check;

update public.user_profiles
set role = case role
  when 'super_admin' then 'system_admin'
  when 'admin' then 'station_admin'
  else role
end
where role in ('super_admin', 'admin');

alter table public.user_profiles
  add constraint user_profiles_role_check
  check (
    role = any (
      array[
        'standard_user'::text,
        'system_admin'::text,
        'central_admin'::text,
        'station_admin'::text,
        'field_officer'::text
      ]
    )
  );

create index if not exists user_profiles_assigned_station_id_idx
  on public.user_profiles(assigned_station_id);

create or replace function public.guard_station_hierarchy_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if new.station_type is distinct from old.station_type then
    if new.station_type <> 'station'
      and exists (
        select 1
        from public.user_profiles
        where assigned_station_id = old.id
          and role in ('station_admin', 'field_officer')
      ) then
      raise exception 'Reassign station staff before changing this station type.';
    end if;

    if new.station_type <> 'cps'
      and exists (
        select 1
        from public.user_profiles
        where assigned_station_id = old.id
          and role = 'central_admin'
      ) then
      raise exception 'Reassign Central Admins before changing this CPS type.';
    end if;

    if new.station_type <> 'cps'
      and exists (
        select 1
        from public.police_stations
        where parent_station_id = old.id
      ) then
      raise exception 'Reassign child stations before changing this CPS type.';
    end if;
  end if;

  return new;
end;
$function$;

drop trigger if exists guard_station_hierarchy_change
  on public.police_stations;
create trigger guard_station_hierarchy_change
before update of station_type on public.police_stations
for each row
execute function public.guard_station_hierarchy_change();

create or replace function public.current_user_role()
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select up.role
  from public.user_profiles as up
  where up.user_id = (select auth.uid())
    and up.account_status = 'active'
  limit 1;
$$;

create or replace function public.current_user_station_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select up.assigned_station_id
  from public.user_profiles as up
  where up.user_id = (select auth.uid())
    and up.account_status = 'active'
  limit 1;
$$;

create or replace function public.is_system_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(public.current_user_role() = 'system_admin', false);
$$;

create or replace function public.is_super_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select public.is_system_admin();
$$;

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    public.current_user_role() in (
      'system_admin',
      'central_admin',
      'station_admin'
    ),
    false
  );
$$;

create or replace function public.can_access_station(target_station_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  with recursive station_scope(station_id) as (
    select public.current_user_station_id()
    where public.current_user_role() in ('central_admin', 'station_admin', 'field_officer')
      and public.current_user_station_id() is not null
    union
    select ps.id
    from public.police_stations as ps
    join station_scope as scope on ps.parent_station_id = scope.station_id
    where public.current_user_role() = 'central_admin'
  )
  select
    public.is_system_admin()
    or exists (
      select 1
      from station_scope
      where station_scope.station_id = target_station_id
    );
$$;

create or replace function public.can_manage_user(target_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select
    public.is_system_admin()
    or exists (
      select 1
      from public.user_profiles as actor
      join public.user_profiles as target
        on target.user_id = target_user_id
      where actor.user_id = (select auth.uid())
        and actor.account_status = 'active'
        and (
          (
            actor.role = 'central_admin'
            and target.role in ('station_admin', 'field_officer')
            and public.can_access_station(target.assigned_station_id)
          )
          or (
            actor.role = 'station_admin'
            and target.role = 'field_officer'
            and target.assigned_station_id = actor.assigned_station_id
          )
        )
    );
$$;

create or replace function public.can_assign_role(
  target_role text,
  target_station_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select
    (
      public.is_system_admin()
      and (
        (target_role = 'system_admin' and target_station_id is null)
        or (
          target_role = 'central_admin'
          and exists (
            select 1
            from public.police_stations as ps
            where ps.id = target_station_id
              and ps.station_type = 'cps'
          )
        )
        or (
          target_role in ('station_admin', 'field_officer')
          and exists (
            select 1
            from public.police_stations as ps
            where ps.id = target_station_id
              and ps.station_type = 'station'
          )
        )
      )
    )
    or (
      public.current_user_role() = 'central_admin'
      and target_role in ('station_admin', 'field_officer')
      and exists (
        select 1
        from public.police_stations as ps
        where ps.id = target_station_id
          and ps.station_type = 'station'
      )
      and public.can_access_station(target_station_id)
    )
    or (
      public.current_user_role() = 'station_admin'
      and target_role = 'field_officer'
      and target_station_id = public.current_user_station_id()
    );
$$;

create or replace function public.can_create_station(
  target_parent_station_id uuid,
  target_station_type text
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select
    (
      public.is_system_admin()
      and (
        (
          target_station_type = 'cps'
          and target_parent_station_id is null
        )
        or (
          target_station_type in ('station', 'post')
          and (
            target_parent_station_id is null
            or exists (
              select 1
              from public.police_stations as parent
              where parent.id = target_parent_station_id
                and parent.station_type = 'cps'
            )
          )
        )
      )
    )
    or (
      public.current_user_role() = 'central_admin'
      and target_station_type = 'station'
      and target_parent_station_id = public.current_user_station_id()
    );
$$;

create or replace function public.can_manage_station(target_station_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select
    public.is_system_admin()
    or (
      public.current_user_role() = 'central_admin'
      and exists (
        select 1
        from public.police_stations as ps
        where ps.id = target_station_id
          and ps.station_type in ('station', 'post')
          and public.can_access_station(ps.id)
      )
    );
$$;

drop function if exists public.admin_create_user(text, text, text, text, text);

create or replace function public.admin_create_user(
  new_email text,
  new_password text,
  new_first_name text,
  new_last_name text,
  new_role text,
  new_station_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  new_user_id uuid := gen_random_uuid();
  normalized_email text := lower(trim(new_email));
begin
  if auth.uid() is null
    or new_role is null
    or not public.can_assign_role(new_role, new_station_id) then
    raise exception 'Unauthorized to create this role or assignment.';
  end if;

  if normalized_email is null
    or normalized_email = ''
    or new_password is null
    or length(new_password) < 6 then
    raise exception 'A valid email and password of at least 6 characters are required.';
  end if;

  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
    created_at, updated_at, confirmation_token, is_sso_user,
    last_sign_in_at
  )
  values (
    '00000000-0000-0000-0000-000000000000',
    new_user_id,
    'authenticated',
    'authenticated',
    normalized_email,
    extensions.crypt(new_password, extensions.gen_salt('bf')),
    now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    jsonb_build_object(
      'first_name', trim(new_first_name),
      'last_name', trim(new_last_name)
    ),
    now(),
    now(),
    '',
    false,
    now()
  );

  insert into auth.identities (
    id, user_id, identity_data, provider, provider_id,
    last_sign_in_at, created_at, updated_at
  )
  values (
    new_user_id,
    new_user_id,
    jsonb_build_object(
      'sub', new_user_id::text,
      'email', normalized_email,
      'email_verified', true
    ),
    'email',
    normalized_email,
    now(),
    now(),
    now()
  );

  insert into public.user_profiles (
    user_id, first_name, last_name, email, role, assigned_station_id,
    account_status, region, district, sub_county, village_area
  )
  values (
    new_user_id,
    trim(new_first_name),
    trim(new_last_name),
    normalized_email,
    new_role,
    new_station_id,
    'active',
    'System Assigned',
    'System Assigned',
    'System Assigned',
    'Headquarters'
  );

  return new_user_id;
end;
$function$;

create or replace function public.admin_update_user_details(
  target_user_id uuid,
  new_first_name text,
  new_last_name text,
  new_email text,
  new_region text,
  new_district text,
  new_sub_county text,
  new_village_area text
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  normalized_email text := lower(trim(new_email));
begin
  if auth.uid() is null
    or not public.can_manage_user(target_user_id) then
    raise exception 'Unauthorized to edit this account.';
  end if;

  if normalized_email is null
    or normalized_email = ''
    or nullif(trim(new_first_name), '') is null
    or nullif(trim(new_last_name), '') is null then
    raise exception 'First name, last name, and email are required.';
  end if;

  perform 1
  from public.user_profiles
  where user_id = target_user_id
  for update;
  if not found then
    raise exception 'User profile not found.';
  end if;

  update auth.users
  set email = normalized_email,
      raw_user_meta_data = coalesce(raw_user_meta_data, '{}'::jsonb)
        || jsonb_build_object(
          'first_name', trim(new_first_name),
          'last_name', trim(new_last_name)
        ),
      updated_at = now()
  where id = target_user_id;

  if not found then
    raise exception 'Authentication account not found.';
  end if;

  update auth.identities
  set provider_id = normalized_email,
      identity_data = coalesce(identity_data, '{}'::jsonb)
        || jsonb_build_object(
          'sub', target_user_id::text,
          'email', normalized_email
        ),
      updated_at = now()
  where user_id = target_user_id
    and provider = 'email';

  if not found then
    raise exception 'Email identity not found.';
  end if;

  update public.user_profiles
  set first_name = trim(new_first_name),
      last_name = trim(new_last_name),
      email = normalized_email,
      region = nullif(trim(new_region), ''),
      district = nullif(trim(new_district), ''),
      sub_county = nullif(trim(new_sub_county), ''),
      village_area = nullif(trim(new_village_area), '')
  where user_id = target_user_id;
end;
$function$;

create or replace function public.admin_update_user_access(
  target_user_id uuid,
  new_role text,
  new_station_id uuid,
  new_account_status text
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  old_role text;
  old_status text;
begin
  if auth.uid() is null then
    raise exception 'Unauthorized.';
  end if;

  select role, account_status
  into old_role, old_status
  from public.user_profiles
  where user_id = target_user_id
  for update;

  if not found then
    raise exception 'User profile not found.';
  end if;

  if old_role = 'standard_user' then
    if not public.is_system_admin() or new_role <> 'standard_user'
      or new_station_id is not null
      or new_account_status is distinct from old_status then
      raise exception 'Standard-user role and assignment cannot be changed here.';
    end if;
  elsif old_role = 'system_admin' then
    if not public.is_system_admin() then
      raise exception 'Only a System Admin can manage System Admin accounts.';
    end if;
  elsif not public.is_system_admin()
    and not public.can_manage_user(target_user_id) then
    raise exception 'Unauthorized to manage this user.';
  end if;

  if new_role is null
    or new_account_status is null
    or new_role not in (
    'system_admin', 'central_admin', 'station_admin', 'field_officer',
    'standard_user'
  ) or new_account_status not in ('active', 'suspended') then
    raise exception 'Invalid role or account status.';
  end if;

  if new_role <> 'standard_user'
    and not public.can_assign_role(new_role, new_station_id) then
    raise exception 'Unauthorized to assign this role or station.';
  end if;

  if new_role = 'standard_user' and new_station_id is not null then
    raise exception 'Standard users cannot have an administrative station assignment.';
  end if;

  if old_role = 'system_admin'
    and old_status = 'active'
    and (new_role <> 'system_admin' or new_account_status <> 'active')
  then
    perform pg_advisory_xact_lock(20261017, 1);
    if (
      select count(*)
      from public.user_profiles
      where role = 'system_admin'
        and account_status = 'active'
    ) <= 1 then
      raise exception 'Cannot deactivate or demote the last active System Admin.';
    end if;
  end if;

  update public.user_profiles
  set role = new_role,
      assigned_station_id = new_station_id,
      account_status = new_account_status
  where user_id = target_user_id;
end;
$function$;

create or replace function public.admin_reset_password(
  target_user_id uuid,
  new_password text
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if auth.uid() is null
    or not public.can_manage_user(target_user_id) then
    raise exception 'Unauthorized to reset this password.';
  end if;

  if new_password is null or length(new_password) < 6 then
    raise exception 'Password must be at least 6 characters.';
  end if;

  update auth.users
  set encrypted_password = extensions.crypt(
        new_password,
        extensions.gen_salt('bf')
      ),
      updated_at = now()
  where id = target_user_id;

  if not found then
    raise exception 'User account not found.';
  end if;
end;
$function$;

create or replace function public.admin_delete_user(target_user_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  target_role text;
  target_status text;
begin
  if auth.uid() is null
    or target_user_id = auth.uid()
    or not public.can_manage_user(target_user_id) then
    raise exception 'Unauthorized to delete this user.';
  end if;

  select role, account_status
  into target_role, target_status
  from public.user_profiles
  where user_id = target_user_id
  for update;

  if not found then
    raise exception 'User profile not found.';
  end if;

  if target_role = 'system_admin'
    and target_status = 'active'
  then
    perform pg_advisory_xact_lock(20261017, 1);
    if (
      select count(*)
      from public.user_profiles
      where role = 'system_admin'
        and account_status = 'active'
    ) <= 1 then
      raise exception 'Cannot delete the last active System Admin.';
    end if;
  end if;

  if target_role = 'standard_user' and not public.is_system_admin() then
    raise exception 'Only a System Admin can delete a standard-user account.';
  end if;

  delete from auth.users where id = target_user_id;
  if not found then
    raise exception 'User account not found.';
  end if;
end;
$function$;

drop policy if exists profile_select_policy on public.user_profiles;
create policy profile_select_policy
on public.user_profiles
for select
to authenticated
using (
  user_id = (select auth.uid())
  or (
    role = 'standard_user'
    and public.is_admin()
  )
  or public.can_manage_user(user_id)
);

drop policy if exists profile_insert_policy on public.user_profiles;
create policy profile_insert_policy
on public.user_profiles
for insert
to authenticated
with check (
  user_id = (select auth.uid())
  and role = 'standard_user'
  and assigned_station_id is null
  and account_status = 'active'
);

drop policy if exists profile_update_policy on public.user_profiles;
drop policy if exists profile_update_own_policy on public.user_profiles;
create policy profile_update_own_policy
on public.user_profiles
for update
to authenticated
using (user_id = (select auth.uid()))
with check (user_id = (select auth.uid()));

revoke update on public.user_profiles from public, anon, authenticated;
grant update (
  first_name, last_name, region, district, sub_county, village_area
) on public.user_profiles to authenticated;

drop policy if exists "Admins can view all incidents" on public.incidents;
drop policy if exists "Admins can update incidents" on public.incidents;

create policy "Scoped staff can view assigned incidents"
on public.incidents
for select
to authenticated
using (
  user_id = (select auth.uid())
  or (
    public.current_user_role() in (
      'system_admin', 'central_admin', 'station_admin', 'field_officer'
    )
    and public.can_access_station(police_station_id)
  )
);

create policy "Scoped staff can update assigned incidents"
on public.incidents
for update
to authenticated
using (
  user_id = (select auth.uid())
  or (
    public.current_user_role() in (
      'system_admin', 'central_admin', 'station_admin', 'field_officer'
    )
    and public.can_access_station(police_station_id)
  )
)
with check (
  user_id = (select auth.uid())
  or (
    public.current_user_role() in (
      'system_admin', 'central_admin', 'station_admin', 'field_officer'
    )
    and public.can_access_station(police_station_id)
  )
);

drop policy if exists "Anyone can view police stations" on public.police_stations;
create policy "Anyone can view police stations"
on public.police_stations
for select
to public
using (true);

drop policy if exists police_stations_admin_insert on public.police_stations;
create policy police_stations_admin_insert
on public.police_stations
for insert
to authenticated
with check (public.can_create_station(parent_station_id, station_type));

drop policy if exists police_stations_admin_update on public.police_stations;
create policy police_stations_admin_update
on public.police_stations
for update
to authenticated
using (public.can_manage_station(id))
with check (
  (
    public.is_system_admin()
    and (
      (station_type = 'cps' and parent_station_id is null)
      or (
        station_type in ('station', 'post')
        and (
          parent_station_id is null
          or exists (
            select 1
            from public.police_stations as parent
            where parent.id = parent_station_id
              and parent.station_type = 'cps'
          )
        )
      )
    )
  )
  or (
    public.current_user_role() = 'central_admin'
    and station_type = 'station'
    and parent_station_id = public.current_user_station_id()
  )
);

drop policy if exists police_stations_admin_delete on public.police_stations;
create policy police_stations_admin_delete
on public.police_stations
for delete
to authenticated
using (
  public.is_system_admin()
  or (
    public.current_user_role() = 'central_admin'
    and station_type in ('station', 'post')
    and public.can_access_station(id)
  )
);

grant insert, update, delete on public.police_stations to authenticated;

revoke all on function public.current_user_role() from public, anon;
revoke all on function public.current_user_station_id() from public, anon;
revoke all on function public.guard_station_hierarchy_change() from public, anon;
revoke all on function public.is_system_admin() from public, anon;
revoke all on function public.is_super_admin() from public, anon;
revoke all on function public.is_admin() from public, anon;
revoke all on function public.can_access_station(uuid) from public, anon;
revoke all on function public.can_manage_user(uuid) from public, anon;
revoke all on function public.can_assign_role(text, uuid) from public, anon;
revoke all on function public.can_create_station(uuid, text) from public, anon;
revoke all on function public.can_manage_station(uuid) from public, anon;
revoke all on function public.admin_create_user(text, text, text, text, text, uuid)
  from public, anon;
revoke all on function public.admin_update_user_details(
  uuid, text, text, text, text, text, text, text
) from public, anon;
revoke all on function public.admin_update_user_access(uuid, text, uuid, text)
  from public, anon;
revoke all on function public.admin_reset_password(uuid, text) from public, anon;
revoke all on function public.admin_delete_user(uuid) from public, anon;

grant execute on function public.current_user_role() to authenticated;
grant execute on function public.current_user_station_id() to authenticated;
grant execute on function public.is_system_admin() to authenticated;
grant execute on function public.is_super_admin() to authenticated;
grant execute on function public.is_admin() to authenticated;
grant execute on function public.can_access_station(uuid) to authenticated;
grant execute on function public.can_manage_user(uuid) to authenticated;
grant execute on function public.can_assign_role(text, uuid) to authenticated;
grant execute on function public.can_create_station(uuid, text) to authenticated;
grant execute on function public.can_manage_station(uuid) to authenticated;
grant execute on function public.admin_create_user(text, text, text, text, text, uuid)
  to authenticated;
grant execute on function public.admin_update_user_details(
  uuid, text, text, text, text, text, text, text
) to authenticated;
grant execute on function public.admin_update_user_access(uuid, text, uuid, text)
  to authenticated;
grant execute on function public.admin_reset_password(uuid, text)
  to authenticated;
grant execute on function public.admin_delete_user(uuid) to authenticated;

commit;
