begin;

create schema evalink_private;
revoke all on schema evalink_private from public, anon, authenticated;

create type public.evaluator_type as enum ('peer', 'professional', 'community');
create type public.project_visibility as enum ('private', 'community');
create type public.assignment_status as enum ('invited', 'accepted', 'declined', 'submitted');
create type public.report_status as enum ('open', 'resolved', 'dismissed');

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null check (char_length(btrim(display_name)) between 1 and 80),
  headline text not null default '' check (char_length(headline) <= 120),
  expertise text not null default '' check (char_length(expertise) <= 240),
  portfolio_url text check (char_length(portfolio_url) <= 500 and portfolio_url ~ '^https://[^[:space:]]+$'),
  directory_visible boolean not null default false,
  evaluator_type public.evaluator_type not null default 'community',
  email_confirmed boolean not null default false,
  created_at timestamptz not null default now()
);

create table public.rubrics (
  id text primary key,
  name text not null,
  version integer not null check (version > 0)
);

create table public.rubric_criteria (
  rubric_id text not null references public.rubrics(id),
  criterion_key text not null,
  position integer not null check (position > 0),
  label text not null,
  prompt text not null,
  primary key (rubric_id, criterion_key),
  unique (rubric_id, position)
);

create table public.projects (
  id uuid primary key default gen_random_uuid(),
  creator_id uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  title text not null check (char_length(btrim(title)) between 1 and 100),
  category text not null check (category in ('Research', 'Prototype', 'Game', 'Creative work', 'Other')),
  summary text not null check (char_length(btrim(summary)) between 1 and 2000),
  artifact_url text check (char_length(artifact_url) <= 500 and artifact_url ~ '^https://[^[:space:]]+$'),
  visibility public.project_visibility not null default 'private',
  rubric_id text not null references public.rubrics(id),
  created_at timestamptz not null default now(),
  unique (id, creator_id)
);

create table public.review_assignments (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null,
  creator_id uuid not null default auth.uid(),
  evaluator_id uuid not null references public.profiles(id) on delete cascade,
  status public.assignment_status not null default 'invited',
  requested_at timestamptz not null default now(),
  responded_at timestamptz,
  submitted_at timestamptz,
  foreign key (project_id, creator_id) references public.projects(id, creator_id) on delete cascade,
  unique (project_id, evaluator_id),
  check (creator_id <> evaluator_id)
);

create table public.reviews (
  assignment_id uuid primary key references public.review_assignments(id) on delete cascade,
  scores jsonb not null check (jsonb_typeof(scores) = 'object'),
  feedback text not null check (char_length(btrim(feedback)) between 1 and 4000),
  no_conflict boolean not null check (no_conflict),
  created_at timestamptz not null default now()
);

create table public.project_reports (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete cascade,
  reporter_id uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  reason text not null check (char_length(btrim(reason)) between 1 and 500),
  status public.report_status not null default 'open',
  resolved_by uuid references auth.users(id) on delete set null,
  resolved_at timestamptz,
  created_at timestamptz not null default now(),
  unique (project_id, reporter_id)
);

create index projects_creator_created_idx on public.projects (creator_id, created_at desc);
create index projects_community_created_idx on public.projects (created_at desc) where visibility = 'community';
create index profiles_directory_name_idx on public.profiles (display_name) where directory_visible;
create index review_assignments_evaluator_requested_idx on public.review_assignments (evaluator_id, requested_at desc);
create index review_assignments_creator_requested_idx on public.review_assignments (creator_id, requested_at desc);
create index project_reports_reporter_idx on public.project_reports (reporter_id);
create index project_reports_status_created_idx on public.project_reports (status, created_at desc);

insert into public.rubrics (id, name, version) values
  ('general-v1', 'General feedback', 1),
  ('research-v1', 'Research review', 1),
  ('prototype-v1', 'Prototype review', 1),
  ('game-v1', 'Playtest', 1);

insert into public.rubric_criteria (rubric_id, criterion_key, position, label, prompt) values
  ('general-v1', 'clarity', 1, 'Clarity', 'Is the purpose easy to understand?'),
  ('general-v1', 'execution', 2, 'Execution', 'How well does the work deliver on its goal?'),
  ('general-v1', 'impact', 3, 'Impact', 'How well does the work serve its intended audience?'),
  ('research-v1', 'question', 1, 'Research question', 'Is the question clear and specific?'),
  ('research-v1', 'method', 2, 'Method', 'Does the method fit the research question?'),
  ('research-v1', 'evidence', 3, 'Evidence', 'Do the findings support the conclusions?'),
  ('prototype-v1', 'purpose', 1, 'Purpose', 'Is the problem and intended user clear?'),
  ('prototype-v1', 'functionality', 2, 'Functionality', 'Does the main flow work as intended?'),
  ('prototype-v1', 'usability', 3, 'Usability', 'Can a first-time user complete the main task?'),
  ('game-v1', 'onboarding', 1, 'Onboarding', 'Can a new player learn the controls and goal?'),
  ('game-v1', 'play', 2, 'Core play', 'Are the core interactions engaging and understandable?'),
  ('game-v1', 'polish', 3, 'Polish', 'Do stability, feedback, and presentation support play?');

create function evalink_private.create_profile()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id, display_name, email_confirmed)
  values (
    new.id,
    coalesce(nullif(left(btrim(new.raw_user_meta_data ->> 'display_name'), 80), ''), 'New member'),
    new.email_confirmed_at is not null
  )
  on conflict (id) do update set email_confirmed = excluded.email_confirmed;
  return new;
end;
$$;

create trigger evalink_create_profile after insert on auth.users
for each row execute function evalink_private.create_profile();

create trigger evalink_sync_profile_confirmation after update of email_confirmed_at on auth.users
for each row when (old.email_confirmed_at is distinct from new.email_confirmed_at)
execute function evalink_private.create_profile();

insert into public.profiles (id, display_name, email_confirmed)
select id, coalesce(nullif(left(btrim(raw_user_meta_data ->> 'display_name'), 80), ''), 'New member'),
  email_confirmed_at is not null
from auth.users on conflict (id) do nothing;

create function evalink_private.guard_assignment_status()
returns trigger language plpgsql set search_path = '' as $$
begin
  if (select auth.uid()) is distinct from old.evaluator_id then
    raise exception 'Only the invited evaluator can respond';
  end if;
  if old.status = 'invited' and new.status in ('accepted', 'declined') then
    new.responded_at := now();
  elsif old.status = 'accepted' and new.status = 'submitted'
    and exists (select 1 from public.reviews where assignment_id = old.id) then
    new.submitted_at := now();
  else
    raise exception 'Invalid review status transition';
  end if;
  return new;
end;
$$;

create trigger evalink_guard_assignment_status
before update of status on public.review_assignments
for each row execute function evalink_private.guard_assignment_status();

create function evalink_private.submit_review()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  assignment public.review_assignments%rowtype;
  assigned_rubric text;
  expected_criteria integer;
begin
  select * into assignment from public.review_assignments
    where id = new.assignment_id for update;
  if not found or (select auth.uid()) is distinct from assignment.evaluator_id
    or assignment.status <> 'accepted' then
    raise exception 'Review is unavailable';
  end if;

  select rubric_id into assigned_rubric from public.projects where id = assignment.project_id;
  select count(*) into expected_criteria from public.rubric_criteria where rubric_id = assigned_rubric;
  if expected_criteria = 0
    or (select count(*) from jsonb_object_keys(new.scores)) <> expected_criteria
    or exists (
      select 1 from public.rubric_criteria c
      where c.rubric_id = assigned_rubric
      and ((new.scores ->> c.criterion_key) is null
        or jsonb_typeof(new.scores -> c.criterion_key) <> 'number'
        or (new.scores ->> c.criterion_key) !~ '^[1-5]$')
    ) then
    raise exception 'Each rubric criterion requires a score from 1 to 5';
  end if;

  update public.review_assignments set status = 'submitted' where id = assignment.id;
  return new;
end;
$$;

create trigger evalink_submit_review after insert on public.reviews
for each row execute function evalink_private.submit_review();

create function evalink_private.resolve_report()
returns trigger language plpgsql set search_path = '' as $$
begin
  if old.status <> 'open' or new.status not in ('resolved', 'dismissed') then
    raise exception 'Invalid report status transition';
  end if;
  new.resolved_by := (select auth.uid());
  new.resolved_at := now();
  return new;
end;
$$;

create trigger evalink_resolve_report before update of status on public.project_reports
for each row execute function evalink_private.resolve_report();

revoke execute on all functions in schema evalink_private from public, anon, authenticated;

alter table public.profiles enable row level security;
alter table public.rubrics enable row level security;
alter table public.rubric_criteria enable row level security;
alter table public.projects enable row level security;
alter table public.review_assignments enable row level security;
alter table public.reviews enable row level security;
alter table public.project_reports enable row level security;

revoke all on public.profiles, public.rubrics, public.rubric_criteria, public.projects,
  public.review_assignments, public.reviews, public.project_reports from public, anon, authenticated;

grant select on public.profiles, public.rubrics, public.rubric_criteria, public.projects,
  public.review_assignments, public.reviews, public.project_reports to authenticated;
grant update (display_name, headline, expertise, portfolio_url, directory_visible, evaluator_type)
  on public.profiles to authenticated;
grant insert (title, category, summary, artifact_url, visibility, rubric_id) on public.projects to authenticated;
grant update (visibility) on public.projects to authenticated;
grant insert (project_id, evaluator_id) on public.review_assignments to authenticated;
grant update (status) on public.review_assignments to authenticated;
grant insert (assignment_id, scores, feedback, no_conflict) on public.reviews to authenticated;
grant insert (project_id, reason) on public.project_reports to authenticated;
grant update (status) on public.project_reports to authenticated;

create policy profiles_read on public.profiles for select to authenticated
  using (id = (select auth.uid()) or directory_visible);

create policy profiles_update_own on public.profiles for update to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));

create policy rubrics_read on public.rubrics for select to authenticated using (true);
create policy rubric_criteria_read on public.rubric_criteria for select to authenticated using (true);

create policy projects_read on public.projects for select to authenticated using (
  creator_id = (select auth.uid()) or visibility = 'community' or exists (
    select 1 from public.review_assignments a where a.project_id = projects.id
    and a.evaluator_id = (select auth.uid()) and a.status <> 'declined'
  )
);
create policy projects_insert_own on public.projects for insert to authenticated
  with check (creator_id = (select auth.uid()));
create policy projects_update_own on public.projects for update to authenticated
  using (creator_id = (select auth.uid())) with check (creator_id = (select auth.uid()));

create policy assignments_read_participant on public.review_assignments for select to authenticated
  using (creator_id = (select auth.uid()) or evaluator_id = (select auth.uid()));
create policy assignments_invite on public.review_assignments for insert to authenticated
  with check (creator_id = (select auth.uid()) and exists (
    select 1 from public.profiles p where p.id = evaluator_id and p.directory_visible
  ));
create policy assignments_respond on public.review_assignments for update to authenticated
  using (evaluator_id = (select auth.uid())) with check (evaluator_id = (select auth.uid()));

create policy reviews_read_participant on public.reviews for select to authenticated using (
  exists (select 1 from public.review_assignments a where a.id = assignment_id
    and (a.creator_id = (select auth.uid()) or a.evaluator_id = (select auth.uid())))
);
create policy reviews_insert_assigned on public.reviews for insert to authenticated with check (
  exists (select 1 from public.review_assignments a where a.id = assignment_id
    and a.evaluator_id = (select auth.uid()) and a.status = 'accepted')
);

create policy reports_create on public.project_reports for insert to authenticated with check (
  reporter_id = (select auth.uid()) and exists (
    select 1 from public.projects p where p.id = project_id and p.creator_id <> (select auth.uid())
  )
);
create policy reports_read on public.project_reports for select to authenticated using (
  reporter_id = (select auth.uid()) or (select auth.jwt()) -> 'app_metadata' ->> 'evalink_moderator' = 'true'
);
create policy reports_moderate on public.project_reports for update to authenticated
  using ((select auth.jwt()) -> 'app_metadata' ->> 'evalink_moderator' = 'true')
  with check ((select auth.jwt()) -> 'app_metadata' ->> 'evalink_moderator' = 'true');

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table public.review_assignments;
  end if;
end;
$$;

commit;
