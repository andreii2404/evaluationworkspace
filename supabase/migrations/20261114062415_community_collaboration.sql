begin;

-- The hosted pilot was empty. Refuse to purge any pilot records added since that check.
do $$
begin
  if exists (select 1 from public.professional_orders)
    or exists (select 1 from public.professional_services)
    or exists (select 1 from storage.objects where bucket_id = 'professional-review-files') then
    raise exception 'Archive or remove pilot data before retiring the marketplace.';
  end if;
end;
$$;
drop policy professional_draft_read on storage.objects;
drop policy professional_draft_upload on storage.objects;
drop policy professional_draft_remove on storage.objects;
drop function public.advance_professional_order(uuid, text, timestamptz, text, integer, integer, text[], boolean);
drop function public.moderate_professional_listing(uuid, boolean, timestamptz);
drop table public.professional_order_events, public.professional_revision_items,
  public.professional_orders, public.professional_services;
drop schema professional_private cascade;

grant usage on schema evalink_private to authenticated;

create table public.project_collaborators (
  project_id uuid not null references public.projects(id) on delete cascade,
  member_id uuid not null references public.profiles(id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (project_id, member_id)
);
create index project_collaborators_member_idx on public.project_collaborators (member_id, project_id);
create index review_assignments_evaluator_project_idx on public.review_assignments (evaluator_id, project_id);

create function evalink_private.project_is_owner(p_project uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.projects p where p.id = p_project and p.creator_id = (select auth.uid())
  );
$$;

create function evalink_private.project_is_team(p_project uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select evalink_private.project_is_owner(p_project) or exists (
    select 1 from public.project_collaborators c where c.project_id = p_project and c.member_id = (select auth.uid())
  );
$$;

create function evalink_private.eligible_collaborator(p_project uuid, p_member uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select evalink_private.project_is_owner(p_project) and p_member <> (select auth.uid())
    and not exists (
      select 1 from public.review_assignments a
      where a.project_id = p_project and a.evaluator_id = p_member and a.status <> 'declined'
    ) and exists (
      select 1 from public.profiles p
      where p.id = p_member and (p.directory_visible or exists (
        select 1 from public.member_connections c where c.status = 'accepted'
        and ((c.requester_id = (select auth.uid()) and c.recipient_id = p_member)
          or (c.recipient_id = (select auth.uid()) and c.requester_id = p_member))
      ))
    );
$$;

create function evalink_private.eligible_reviewer(p_project uuid, p_reviewer uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select evalink_private.project_is_owner(p_project) and p_reviewer <> (select auth.uid())
    and not exists (
      select 1 from public.project_collaborators c where c.project_id = p_project and c.member_id = p_reviewer
    ) and exists (select 1 from public.profiles p where p.id = p_reviewer and p.directory_visible);
$$;

create function evalink_private.lock_project_access()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(new.project_id::text, 302));
  if tg_table_name = 'project_collaborators' then
    if not evalink_private.eligible_collaborator(new.project_id, new.member_id) then
      raise exception 'Choose a member who is not evaluating this project.' using errcode = '42501';
    end if;
  elsif not evalink_private.eligible_reviewer(new.project_id, new.evaluator_id) then
    raise exception 'Choose an independent, directory-visible evaluator.' using errcode = '42501';
  end if;
  return new;
end;
$$;
create trigger project_collaborator_access_guard before insert on public.project_collaborators
for each row execute function evalink_private.lock_project_access();
create trigger review_assignment_team_guard before insert on public.review_assignments
for each row execute function evalink_private.lock_project_access();

alter table public.project_collaborators enable row level security;
revoke all on public.project_collaborators from public, anon, authenticated;
grant select, delete on public.project_collaborators to authenticated;
grant insert (project_id, member_id) on public.project_collaborators to authenticated;
create policy project_team_read on public.project_collaborators for select to authenticated
using (evalink_private.project_is_team(project_id));
create policy project_team_add on public.project_collaborators for insert to authenticated
with check (evalink_private.eligible_collaborator(project_id, member_id));
create policy project_team_remove on public.project_collaborators for delete to authenticated
using (evalink_private.project_is_owner(project_id) or member_id = (select auth.uid()));

create policy projects_read_team on public.projects for select to authenticated
using (evalink_private.project_is_team(id));
create policy assignments_read_team on public.review_assignments for select to authenticated
using (evalink_private.project_is_team(project_id));

drop policy reviews_read_participant on public.reviews;
create policy reviews_read_participant on public.reviews for select to authenticated using (
  exists (
    select 1 from public.review_assignments a where a.id = assignment_id
    and (evalink_private.project_is_team(a.project_id) or a.evaluator_id = (select auth.uid()))
  )
);

create policy attached_questionnaires_read_team on storage.objects for select to authenticated
using (bucket_id = 'project-questionnaires' and exists (
  select 1 from public.projects p where p.questionnaire_file_path = storage.objects.name
  and evalink_private.project_is_team(p.id)
));

-- Optional named rounds create a stable version link for repeat evaluations.
create table public.project_review_rounds (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete cascade,
  label text not null check (length(btrim(label)) between 1 and 80),
  artifact_url text not null check (length(artifact_url) <= 500 and artifact_url ~ '^https://[^/@?#[:space:]]+([/?#][^[:space:]]*)?$'),
  created_at timestamptz not null default now(),
  unique (project_id, id),
  unique (project_id, label)
);
alter table public.review_assignments
  add column round_id uuid,
  add constraint review_assignment_round_fk foreign key (project_id, round_id)
    references public.project_review_rounds(project_id, id) on delete cascade,
  drop constraint review_assignments_project_id_evaluator_id_key,
  add constraint review_assignments_project_round_evaluator unique nulls not distinct (project_id, round_id, evaluator_id);
grant insert (round_id) on public.review_assignments to authenticated;

alter table public.project_review_rounds enable row level security;
revoke all on public.project_review_rounds from public, anon, authenticated;
grant select on public.project_review_rounds to authenticated;
grant insert (project_id, label, artifact_url) on public.project_review_rounds to authenticated;
create policy project_rounds_read on public.project_review_rounds for select to authenticated
using (evalink_private.project_is_team(project_id) or exists (
  select 1 from public.review_assignments a where a.round_id = project_review_rounds.id
  and a.evaluator_id = (select auth.uid()) and a.status <> 'declined'
));
create policy project_rounds_create on public.project_review_rounds for insert to authenticated
with check (evalink_private.project_is_owner(project_id));

create function evalink_private.review_can_discuss(p_assignment uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.review_assignments a where a.id = p_assignment and a.status <> 'declined'
    and (a.evaluator_id = (select auth.uid()) or evalink_private.project_is_team(a.project_id))
  );
$$;

create table public.review_messages (
  id uuid primary key default gen_random_uuid(),
  assignment_id uuid not null references public.review_assignments(id) on delete cascade,
  sender_id uuid default auth.uid() references public.profiles(id) on delete set null,
  body text not null check (length(btrim(body)) between 1 and 2000),
  created_at timestamptz not null default now()
);
create index review_messages_assignment_idx on public.review_messages (assignment_id, created_at desc);
alter table public.review_messages enable row level security;
revoke all on public.review_messages from public, anon, authenticated;
grant select on public.review_messages to authenticated;
grant insert (assignment_id, body) on public.review_messages to authenticated;
create policy review_messages_read on public.review_messages for select to authenticated
using (evalink_private.review_can_discuss(assignment_id));
create policy review_messages_send on public.review_messages for insert to authenticated
with check (sender_id = (select auth.uid()) and evalink_private.review_can_discuss(assignment_id));

create table public.workspace_notifications (
  id uuid primary key default gen_random_uuid(),
  recipient_id uuid not null references public.profiles(id) on delete cascade,
  project_id uuid not null references public.projects(id) on delete cascade,
  assignment_id uuid references public.review_assignments(id) on delete cascade,
  kind text not null check (kind in ('team', 'invited', 'accepted', 'declined', 'submitted', 'message', 'reminder')),
  created_at timestamptz not null default now(),
  read_at timestamptz
);
create index workspace_notifications_recipient_idx on public.workspace_notifications (recipient_id, created_at desc);
create index workspace_notifications_project_idx on public.workspace_notifications (project_id);
create index workspace_notifications_reminder_idx on public.workspace_notifications (assignment_id, created_at desc)
  where kind = 'reminder';
create index workspace_notifications_assignment_idx on public.workspace_notifications (assignment_id);
alter table public.workspace_notifications enable row level security;
revoke all on public.workspace_notifications from public, anon, authenticated;
grant select on public.workspace_notifications to authenticated;
grant update (read_at) on public.workspace_notifications to authenticated;
create policy workspace_notifications_read on public.workspace_notifications for select to authenticated
using (recipient_id = (select auth.uid()));
create policy workspace_notifications_mark on public.workspace_notifications for update to authenticated
using (recipient_id = (select auth.uid())) with check (recipient_id = (select auth.uid()));

create function evalink_private.notify_review_team(p_project uuid, p_assignment uuid, p_kind text, p_sender uuid)
returns void language sql security definer set search_path = '' as $$
  insert into public.workspace_notifications (recipient_id, project_id, assignment_id, kind)
  select members.id, p_project, p_assignment, p_kind from (
    select p.creator_id as id from public.projects p where p.id = p_project
    union all select c.member_id from public.project_collaborators c where c.project_id = p_project
  ) members where members.id is distinct from p_sender;
$$;

create function evalink_private.send_workspace_notification()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  assignment public.review_assignments%rowtype;
begin
  if tg_table_name = 'project_collaborators' then
    insert into public.workspace_notifications (recipient_id, project_id, kind)
    values (new.member_id, new.project_id, 'team');
  elsif tg_table_name = 'review_assignments' then
    if tg_op = 'INSERT' then
      insert into public.workspace_notifications (recipient_id, project_id, assignment_id, kind)
      values (new.evaluator_id, new.project_id, new.id, 'invited');
    elsif new.status is distinct from old.status then
      perform evalink_private.notify_review_team(new.project_id, new.id, new.status::text, new.evaluator_id);
    end if;
  else
    select * into assignment from public.review_assignments a where a.id = new.assignment_id;
    perform evalink_private.notify_review_team(assignment.project_id, assignment.id, 'message', new.sender_id);
    if assignment.evaluator_id is distinct from new.sender_id then
      insert into public.workspace_notifications (recipient_id, project_id, assignment_id, kind)
      values (assignment.evaluator_id, assignment.project_id, assignment.id, 'message');
    end if;
  end if;
  return new;
end;
$$;
create trigger notify_project_collaborator after insert on public.project_collaborators
for each row execute function evalink_private.send_workspace_notification();
create trigger notify_review_assignment after insert or update of status on public.review_assignments
for each row execute function evalink_private.send_workspace_notification();
create trigger notify_review_message after insert on public.review_messages
for each row execute function evalink_private.send_workspace_notification();

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table public.workspace_notifications, public.review_messages;
  end if;
end;
$$;

create function evalink_private.send_review_reminder(p_assignment uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  assignment public.review_assignments%rowtype;
begin
  select * into assignment from public.review_assignments a where a.id = p_assignment for update;
  if not found or not evalink_private.project_is_owner(assignment.project_id)
    or assignment.status not in ('invited', 'accepted') then
    raise exception 'This review cannot be reminded.' using errcode = '42501';
  end if;
  if exists (
    select 1 from public.workspace_notifications n
    where n.assignment_id = p_assignment and n.kind in ('reminder', 'invited')
    and n.created_at > now() - interval '24 hours'
  ) then
    raise exception 'A reminder can be sent 24 hours after the last invitation or reminder.';
  end if;
  insert into public.workspace_notifications (recipient_id, project_id, assignment_id, kind)
  values (assignment.evaluator_id, assignment.project_id, assignment.id, 'reminder');
end;
$$;
create function public.send_review_reminder(p_assignment uuid)
returns void language sql security invoker set search_path = '' as $$
  select evalink_private.send_review_reminder(p_assignment);
$$;

create table public.project_revision_tasks (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete cascade,
  assignment_id uuid references public.review_assignments(id) on delete cascade,
  description text not null check (length(btrim(description)) between 1 and 240),
  done boolean not null default false,
  created_at timestamptz not null default now()
);
create index project_revision_tasks_project_idx on public.project_revision_tasks (project_id, created_at desc);
create index project_revision_tasks_assignment_idx on public.project_revision_tasks (assignment_id);
alter table public.project_revision_tasks enable row level security;
revoke all on public.project_revision_tasks from public, anon, authenticated;
grant select, delete on public.project_revision_tasks to authenticated;
grant insert (project_id, assignment_id, description), update (done) on public.project_revision_tasks to authenticated;
create policy project_revision_read on public.project_revision_tasks for select to authenticated
using (evalink_private.project_is_team(project_id));
create policy project_revision_add on public.project_revision_tasks for insert to authenticated
with check (evalink_private.project_is_team(project_id) and (assignment_id is null or exists (
  select 1 from public.review_assignments a where a.id = assignment_id
  and a.project_id = project_revision_tasks.project_id and a.status = 'submitted'
)));
create policy project_revision_check on public.project_revision_tasks for update to authenticated
using (evalink_private.project_is_team(project_id)) with check (evalink_private.project_is_team(project_id));
create policy project_revision_remove on public.project_revision_tasks for delete to authenticated
using (evalink_private.project_is_team(project_id));

-- Expose a completion count without revealing a review, project, or respondent.
create function evalink_private.completed_review_count(p_evaluator uuid)
returns bigint language sql stable security definer set search_path = '' as $$
  select count(*) from public.review_assignments a
  where a.evaluator_id = p_evaluator and a.status = 'submitted' and (select auth.uid()) is not null
  and exists (select 1 from public.profiles p where p.id = p_evaluator
    and (p.directory_visible or p.id = (select auth.uid())));
$$;
create function public.completed_review_count(p_evaluator uuid)
returns bigint language sql security invoker set search_path = '' as $$
  select evalink_private.completed_review_count(p_evaluator);
$$;

create table public.credential_requests (
  id uuid primary key default gen_random_uuid(),
  applicant_id uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  kind text not null check (kind in ('Affiliation', 'Certification', 'Professional license', 'Portfolio')),
  label text not null check (length(btrim(label)) between 3 and 120),
  evidence_url text not null check (length(evidence_url) <= 500 and evidence_url ~ '^https://[^/@?#[:space:]]+([/?#][^[:space:]]*)?$'),
  status text not null default 'pending' check (status in ('pending', 'approved', 'declined')),
  decision_note text check (length(btrim(decision_note)) between 3 and 800),
  created_at timestamptz not null default now()
);
create index credential_requests_applicant_idx on public.credential_requests (applicant_id, created_at desc);
create unique index credential_request_pending_idx on public.credential_requests (applicant_id, kind) where status = 'pending';
create table public.checked_credentials (
  request_id uuid primary key references public.credential_requests(id) on delete cascade,
  member_id uuid not null references public.profiles(id) on delete cascade,
  kind text not null,
  label text not null,
  checked_at timestamptz not null default now()
);
create index checked_credentials_member_idx on public.checked_credentials (member_id);

alter table public.credential_requests enable row level security;
alter table public.checked_credentials enable row level security;
revoke all on public.credential_requests, public.checked_credentials from public, anon, authenticated;
grant select on public.credential_requests, public.checked_credentials to authenticated;
grant insert (kind, label, evidence_url) on public.credential_requests to authenticated;
grant delete on public.credential_requests to authenticated;
create policy credential_requests_read on public.credential_requests for select to authenticated
using (applicant_id = (select auth.uid())
  or (select auth.jwt()) -> 'app_metadata' ->> 'evalink_moderator' = 'true');
create policy credential_requests_apply on public.credential_requests for insert to authenticated
with check (applicant_id = (select auth.uid()) and exists (
  select 1 from public.profiles p where p.id = (select auth.uid()) and p.email_confirmed
));
create policy credential_requests_remove on public.credential_requests for delete to authenticated
using (applicant_id = (select auth.uid()));
create policy checked_credentials_read on public.checked_credentials for select to authenticated
using (member_id = (select auth.uid()) or exists (
  select 1 from public.profiles p where p.id = member_id and p.directory_visible
));

create function evalink_private.decide_credential(p_id uuid, p_approve boolean, p_note text)
returns void language plpgsql security definer set search_path = '' as $$
declare
  request public.credential_requests%rowtype;
begin
  if (select auth.uid()) is null or coalesce((select auth.jwt()) -> 'app_metadata' ->> 'evalink_moderator', '') <> 'true' then
    raise exception 'Only moderators can review credentials.' using errcode = '42501';
  end if;
  update public.credential_requests set status = case when p_approve then 'approved' else 'declined' end,
    decision_note = btrim(p_note)
  where id = p_id and applicant_id <> (select auth.uid())
    and (status = 'pending' or (status = 'approved' and not p_approve))
    and length(btrim(p_note)) between 3 and 800
  returning * into request;
  if not found then raise exception 'The credential changed or is unavailable.'; end if;
  if p_approve then
    insert into public.checked_credentials (request_id, member_id, kind, label)
    values (request.id, request.applicant_id, request.kind, request.label);
  else
    delete from public.checked_credentials where request_id = request.id;
  end if;
end;
$$;
create function public.decide_credential(p_id uuid, p_approve boolean, p_note text)
returns void language sql security invoker set search_path = '' as $$
  select evalink_private.decide_credential(p_id, p_approve, p_note);
$$;

create table public.workspace_folders (
  id uuid primary key default gen_random_uuid(),
  scope text not null check (scope in ('personal', 'project')),
  scope_id uuid not null,
  parent_id uuid,
  name text not null check (length(btrim(name)) between 1 and 100 and name !~ '[/\\[:cntrl:]]'
    and btrim(name) not in ('.', '..')),
  created_at timestamptz not null default now(),
  personal_owner uuid generated always as (case when scope = 'personal' then scope_id end) stored
    references public.profiles(id) on delete cascade,
  project_owner uuid generated always as (case when scope = 'project' then scope_id end) stored
    references public.projects(id) on delete cascade,
  unique (scope, scope_id, id),
  foreign key (scope, scope_id, parent_id) references public.workspace_folders(scope, scope_id, id),
  unique nulls not distinct (scope, scope_id, parent_id, name)
);
create index workspace_folders_parent_idx on public.workspace_folders (scope, scope_id, parent_id);
create index workspace_folders_owner_idx on public.workspace_folders (personal_owner) where personal_owner is not null;
create index workspace_folders_project_idx on public.workspace_folders (project_owner) where project_owner is not null;

create function evalink_private.workspace_scope_access(p_scope text, p_scope_id text)
returns boolean language sql stable set search_path = '' as $$
  select case
    when p_scope_id !~ '^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$' then false
    when p_scope = 'personal' then (select auth.uid())::text = p_scope_id
    when p_scope = 'project' then evalink_private.project_is_team(p_scope_id::uuid)
    else false end;
$$;

create function evalink_private.workspace_file_access(p_name text, p_write boolean)
returns boolean language sql stable set search_path = '' as $$
  select evalink_private.workspace_scope_access(parts[1], parts[2])
    and cardinality(parts) = 4 and length(parts[4]) between 1 and 180
    and (not p_write or parts[4] ~* '\.(pdf|docx|xlsx|pptx|csv|txt|md|png|jpg|jpeg|webp|zip)$')
    and (parts[3] = 'root' or exists (
      select 1 from public.workspace_folders f where f.scope = parts[1]
      and f.scope_id::text = parts[2] and f.id::text = parts[3]
    ))
  from (select string_to_array(p_name, '/') parts) path;
$$;

alter table public.workspace_folders enable row level security;
revoke all on public.workspace_folders from public, anon, authenticated;
grant select on public.workspace_folders to authenticated;
grant insert (scope, scope_id, parent_id, name), update (name) on public.workspace_folders to authenticated;
create policy workspace_folders_read on public.workspace_folders for select to authenticated
using (evalink_private.workspace_scope_access(scope, scope_id::text));
create policy workspace_folders_create on public.workspace_folders for insert to authenticated
with check (evalink_private.workspace_scope_access(scope, scope_id::text));
create policy workspace_folders_rename on public.workspace_folders for update to authenticated
using (evalink_private.workspace_scope_access(scope, scope_id::text))
with check (evalink_private.workspace_scope_access(scope, scope_id::text));

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('workspace-files', 'workspace-files', false, 10485760, array[
  'application/pdf', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'application/vnd.openxmlformats-officedocument.presentationml.presentation',
  'text/csv', 'text/plain', 'text/markdown', 'image/png', 'image/jpeg', 'image/webp', 'application/zip'
]);
create policy workspace_files_read on storage.objects for select to authenticated
using (bucket_id = 'workspace-files' and evalink_private.workspace_file_access(name, false));
create policy workspace_files_upload on storage.objects for insert to authenticated
with check (bucket_id = 'workspace-files' and evalink_private.workspace_file_access(name, true));
create policy workspace_files_change on storage.objects for update to authenticated
using (bucket_id = 'workspace-files' and evalink_private.workspace_file_access(name, false))
with check (bucket_id = 'workspace-files' and evalink_private.workspace_file_access(name, true));
create policy workspace_files_remove on storage.objects for delete to authenticated
using (bucket_id = 'workspace-files' and evalink_private.workspace_file_access(name, false));

revoke all on function
  evalink_private.project_is_owner(uuid), evalink_private.project_is_team(uuid),
  evalink_private.eligible_collaborator(uuid, uuid), evalink_private.eligible_reviewer(uuid, uuid),
  evalink_private.lock_project_access(), evalink_private.review_can_discuss(uuid),
  evalink_private.notify_review_team(uuid, uuid, text, uuid), evalink_private.send_workspace_notification(),
  evalink_private.send_review_reminder(uuid), public.send_review_reminder(uuid),
  evalink_private.completed_review_count(uuid), public.completed_review_count(uuid),
  evalink_private.decide_credential(uuid, boolean, text), public.decide_credential(uuid, boolean, text),
  evalink_private.workspace_scope_access(text, text), evalink_private.workspace_file_access(text, boolean)
from public, anon, authenticated;

grant execute on function
  evalink_private.project_is_owner(uuid), evalink_private.project_is_team(uuid),
  evalink_private.eligible_collaborator(uuid, uuid), evalink_private.review_can_discuss(uuid),
  evalink_private.send_review_reminder(uuid), public.send_review_reminder(uuid),
  evalink_private.completed_review_count(uuid), public.completed_review_count(uuid),
  evalink_private.decide_credential(uuid, boolean, text), public.decide_credential(uuid, boolean, text),
  evalink_private.workspace_scope_access(text, text), evalink_private.workspace_file_access(text, boolean)
to authenticated;

commit;
