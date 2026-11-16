begin;

create or replace function evalink_private.create_profile()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles as profile (id, display_name, email_confirmed)
  values (
    new.id,
    left(coalesce(
      nullif(btrim(new.raw_user_meta_data ->> 'display_name'), ''),
      nullif(btrim(new.raw_user_meta_data ->> 'full_name'), ''),
      nullif(btrim(new.raw_user_meta_data ->> 'name'), ''),
      'New member'
    ), 80),
    new.email_confirmed_at is not null
  )
  on conflict (id) do update set email_confirmed = excluded.email_confirmed
  where profile.email_confirmed is distinct from excluded.email_confirmed;
  return new;
end;
$$;

revoke execute on function evalink_private.create_profile() from public, anon, authenticated;

drop trigger evalink_sync_profile_confirmation on auth.users;

create trigger evalink_sync_profile_on_auth_change
after update of email_confirmed_at, last_sign_in_at on auth.users
for each row when (
  old.email_confirmed_at is distinct from new.email_confirmed_at or
  old.last_sign_in_at is distinct from new.last_sign_in_at
)
execute function evalink_private.create_profile();

commit;
