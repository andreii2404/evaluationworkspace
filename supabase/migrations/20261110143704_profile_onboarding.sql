begin;

alter table public.profiles
  add column profession text check (
    profession in (
      'student', 'educator', 'researcher', 'it_expert', 'subject_expert',
      'industry_professional', 'independent_creator', 'other'
    )
  ),
  add column onboarding_completed boolean not null default false;

update public.profiles p set onboarding_completed = true
where exists (
  select 1 from auth.users u
  where u.id = p.id and u.last_sign_in_at is not null
);

create function evalink_private.validate_profile_onboarding()
returns trigger language plpgsql set search_path = '' as $$
begin
  if not old.onboarding_completed and new.onboarding_completed
    and new.profession is null then
    raise exception 'Choose a profession to finish account setup';
  end if;
  if old.onboarding_completed and not new.onboarding_completed then
    raise exception 'Account setup has already been completed';
  end if;
  return new;
end;
$$;

revoke execute on function evalink_private.validate_profile_onboarding()
  from public, anon, authenticated;

create trigger evalink_validate_profile_onboarding
before update of onboarding_completed on public.profiles
for each row execute function evalink_private.validate_profile_onboarding();

grant update (profession, onboarding_completed) on public.profiles to authenticated;

commit;
