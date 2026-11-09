create or replace function evalink_private.create_profile()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id, display_name, email_confirmed)
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
  on conflict (id) do update set email_confirmed = excluded.email_confirmed;
  return new;
end;
$$;

revoke execute on function evalink_private.create_profile() from public, anon, authenticated;
