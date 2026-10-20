begin;

create or replace function public.can_update_station(
  target_station_id uuid,
  target_station_type text,
  target_parent_station_id uuid
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
        (target_station_type = 'cps' and target_parent_station_id is null)
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
      and public.can_access_station(target_station_id)
    );
$$;

create or replace function public.admin_assign_station_oc(
  target_station_id uuid,
  target_user_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if auth.uid() is null
    or not public.can_manage_station(target_station_id)
    or not exists (
      select 1
      from public.police_stations as station
      where station.id = target_station_id
        and station.station_type = 'station'
    )
  then
    raise exception 'Unauthorized to assign an OC to this station.';
  end if;

  if target_user_id is not null
    and not exists (
      select 1
      from public.user_profiles as candidate
      where candidate.user_id = target_user_id
        and candidate.assigned_station_id = target_station_id
        and candidate.account_status = 'active'
        and candidate.role in ('station_admin', 'field_officer')
    )
  then
    raise exception 'The selected user must be an active Station Admin or Field Officer assigned to this station.';
  end if;

  update public.user_profiles
  set role = 'field_officer'
  where assigned_station_id = target_station_id
    and role = 'station_admin'
    and user_id is distinct from target_user_id;

  if target_user_id is not null then
    update public.user_profiles
    set role = 'station_admin'
    where user_id = target_user_id;
  end if;
end;
$function$;

drop policy if exists police_stations_admin_update
  on public.police_stations;
create policy police_stations_admin_update
on public.police_stations
for update
to authenticated
using (public.can_manage_station(id))
with check (
  public.can_update_station(id, station_type, parent_station_id)
);

revoke all on function public.can_update_station(uuid, text, uuid)
  from public, anon;
revoke all on function public.admin_assign_station_oc(uuid, uuid)
  from public, anon;

grant execute on function public.can_update_station(uuid, text, uuid)
  to authenticated;
grant execute on function public.admin_assign_station_oc(uuid, uuid)
  to authenticated;

commit;
