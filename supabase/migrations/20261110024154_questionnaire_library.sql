begin;

create function evalink_private.valid_questionnaire_form(form jsonb)
returns boolean language plpgsql immutable set search_path = '' as $$
begin
  if jsonb_typeof(form) is distinct from 'object'
    or jsonb_typeof(form->'title') is distinct from 'string'
    or not coalesce(char_length(btrim(form->>'title')) between 1 and 120, false)
    or jsonb_typeof(form->'instructions') is distinct from 'string'
    or char_length(form->>'instructions') > 1000
    or not coalesce(form->>'scale' in ('standard', 'iso', 'mars'), false)
    or jsonb_typeof(form->'items') is distinct from 'array'
    or jsonb_typeof(form->'fields') is distinct from 'array' then
    return false;
  end if;
  return jsonb_array_length(form->'items') between 1 and 60
    and jsonb_array_length(form->'fields') <= 8
    and not exists (
      select 1 from jsonb_array_elements(form->'items') as entry(item)
      where jsonb_typeof(item) is distinct from 'object'
        or jsonb_typeof(item->'section') is distinct from 'string'
        or char_length(item->>'section') > 100
        or jsonb_typeof(item->'prompt') is distinct from 'string'
        or not coalesce(char_length(btrim(item->>'prompt')) between 1 and 300, false)
    )
    and not exists (
      select 1 from jsonb_array_elements(form->'fields') as entry(field)
      where jsonb_typeof(field) is distinct from 'string'
        or not coalesce(char_length(btrim(field #>> '{}')) between 1 and 80, false)
    );
end;
$$;

revoke execute on function evalink_private.valid_questionnaire_form(jsonb) from public, anon;
grant execute on function evalink_private.valid_questionnaire_form(jsonb) to authenticated;

create table public.saved_questionnaires (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  title text not null check (char_length(btrim(title)) between 1 and 120),
  form jsonb check (form is null or evalink_private.valid_questionnaire_form(form)),
  file_path text unique,
  file_name text,
  created_at timestamptz not null default now(),
  check (num_nonnulls(form, file_path) = 1),
  check (
    (file_path is null and file_name is null)
    or (file_path is not null and file_name is not null
      and file_path ~ ('^' || owner_id::text || '/[0-9a-f]{32}[.](pdf|docx)$')
      and char_length(file_name) between 1 and 180)
  ),
  check (form is null or title = form->>'title')
);
create index saved_questionnaires_owner_created_idx on public.saved_questionnaires (owner_id, created_at desc);

alter table public.saved_questionnaires enable row level security;
revoke all on public.saved_questionnaires from public, anon, authenticated;
grant select on public.saved_questionnaires to authenticated;
grant insert (title, form, file_path, file_name), update (title, form)
  on public.saved_questionnaires to authenticated;

create policy saved_questionnaires_read_own on public.saved_questionnaires for select to authenticated
  using (owner_id = (select auth.uid()));
create policy saved_questionnaires_insert_own on public.saved_questionnaires for insert to authenticated
  with check (
    owner_id = (select auth.uid())
    and (file_path is null or exists (
      select 1 from storage.objects where bucket_id = 'project-questionnaires' and name = file_path
    ))
  );
create policy saved_questionnaires_update_own on public.saved_questionnaires for update to authenticated
  using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()));

alter table public.projects
  add column questionnaire_form jsonb check (
    questionnaire_form is null or evalink_private.valid_questionnaire_form(questionnaire_form)
  ),
  drop constraint projects_questionnaire_check,
  add constraint projects_questionnaire_check check (
    num_nonnulls(rubric_id, custom_questions, questionnaire_file_path, questionnaire_form) <= 1
    and num_nonnulls(rubric_id, custom_questions, questionnaire_file_path, questionnaire_form, questionnaire_url) >= 1
  ),
  drop constraint projects_questionnaire_file_path_key,
  drop constraint projects_questionnaire_file_check,
  add constraint projects_questionnaire_file_check check (
    (questionnaire_file_path is null and questionnaire_file_name is null) or
    (questionnaire_file_path is not null and questionnaire_file_name is not null
      and questionnaire_file_path ~ ('^' || creator_id::text || '/[0-9a-f]{32}[.](pdf|docx)$')
      and char_length(questionnaire_file_name) between 1 and 180)
  );

create index projects_questionnaire_file_path_idx on public.projects (questionnaire_file_path)
  where questionnaire_file_path is not null;

grant insert (questionnaire_form) on public.projects to authenticated;

update storage.buckets set allowed_mime_types = array[
  'application/pdf',
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
] where id = 'project-questionnaires';

drop policy project_questionnaires_upload on storage.objects;
create policy project_questionnaires_upload on storage.objects for insert to authenticated
  with check (
    bucket_id = 'project-questionnaires'
    and name ~ ('^' || (select auth.uid())::text || '/[0-9a-f]{32}[.](pdf|docx)$')
  );

alter policy project_questionnaires_delete_unattached on storage.objects using (
  bucket_id = 'project-questionnaires'
  and split_part(name, '/', 1) = (select auth.uid())::text
  and not exists (select 1 from public.projects p where p.questionnaire_file_path = storage.objects.name)
  and not exists (select 1 from public.saved_questionnaires q where q.file_path = storage.objects.name)
);

alter table public.reviews
  add column respondent_details jsonb not null default '[]'::jsonb;
grant insert (respondent_details) on public.reviews to authenticated;


create or replace function evalink_private.submit_review()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  assignment public.review_assignments%rowtype;
  project public.projects%rowtype;
  expected_keys text[];
begin
  select * into assignment from public.review_assignments
    where id = new.assignment_id for update;
  if not found or (select auth.uid()) is distinct from assignment.evaluator_id
    or assignment.status <> 'accepted' then
    raise exception 'Review is unavailable';
  end if;

  select * into project from public.projects where id = assignment.project_id;
  if project.rubric_id is not null then
    select array_agg(criterion_key order by position) into expected_keys
      from public.rubric_criteria where rubric_id = project.rubric_id;
  elsif project.custom_questions is not null then
    expected_keys := array(
      select 'custom_' || position
      from jsonb_array_elements(project.custom_questions) with ordinality as q(item, position)
      order by position
    );
  elsif project.questionnaire_form is not null then
    expected_keys := array(
      select 'form_' || position
      from jsonb_array_elements(project.questionnaire_form->'items') with ordinality as q(item, position)
      order by position
    );
  else
    expected_keys := array[]::text[];
  end if;

  if jsonb_typeof(new.respondent_details) is distinct from 'array' then
    raise exception 'Respondent details must be an array';
  end if;
  if jsonb_array_length(new.respondent_details) not in (
      0, coalesce(jsonb_array_length(project.questionnaire_form->'fields'), 0))
    or exists (
      select 1 from jsonb_array_elements(new.respondent_details) as entry(value)
      where jsonb_typeof(value) is distinct from 'string' or char_length(value #>> '{}') > 160
    ) then
    raise exception 'Respondent details do not match the questionnaire';
  end if;

  if expected_keys is null
    or (select count(*) from jsonb_object_keys(new.scores)) <> cardinality(expected_keys)
    or exists (
      select 1 from unnest(expected_keys) as expected(key)
      where (new.scores ->> key) is null
        or jsonb_typeof(new.scores -> key) <> 'number'
        or (project.questionnaire_form->>'scale' = 'mars' and (new.scores ->> key) = '5')
        or ((new.scores ->> key) !~ '^[1-5]$'
          and not (coalesce(project.rubric_id in ('website-iso25010-v1', 'mobile-mars-v1'), false)
            and (new.scores ->> key) = '0'))
    ) then
    raise exception 'Each question requires a valid score or an allowed not-assessed response';
  end if;

  update public.review_assignments set status = 'submitted' where id = assignment.id;
  return new;
end;
$$;

commit;

