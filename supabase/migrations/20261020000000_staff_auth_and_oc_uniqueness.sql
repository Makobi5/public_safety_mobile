begin;

do $migration$
begin
  if exists (
    select 1
    from public.user_profiles
    where role in ('central_admin', 'station_admin')
      and assigned_station_id is not null
    group by assigned_station_id
    having count(*) > 1
  ) then
    raise exception
      'Multiple OCs already exist for one or more CPS/stations. Resolve duplicates before applying this migration.';
  end if;
end;
$migration$;

create unique index if not exists user_profiles_one_oc_per_location_idx
  on public.user_profiles(assigned_station_id)
  where role in ('central_admin', 'station_admin')
    and assigned_station_id is not null;

drop function if exists public.admin_create_user(
  text, text, text, text, text, uuid
);

commit;
