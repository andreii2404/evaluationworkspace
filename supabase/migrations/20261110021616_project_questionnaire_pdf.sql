begin;

alter table public.projects
  add column questionnaire_file_path text unique,
  add column questionnaire_file_name text,
  drop constraint projects_questionnaire_check,
  add constraint projects_questionnaire_check check (
    num_nonnulls(rubric_id, custom_questions, questionnaire_file_path) <= 1
    and num_nonnulls(rubric_id, custom_questions, questionnaire_file_path, questionnaire_url) >= 1
  ),
  add constraint projects_questionnaire_file_check check (
    (questionnaire_file_path is null and questionnaire_file_name is null) or
    (questionnaire_file_path is not null and questionnaire_file_name is not null
      and questionnaire_file_path ~ ('^' || creator_id::text || '/[0-9a-f]{32}\.pdf$')
      and char_length(questionnaire_file_name) between 1 and 180)
  );

grant insert (questionnaire_file_path, questionnaire_file_name)
  on public.projects to authenticated;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('project-questionnaires', 'project-questionnaires', false, 5242880, array['application/pdf']);

create policy project_questionnaires_upload on storage.objects for insert to authenticated
  with check (
    bucket_id = 'project-questionnaires'
    and name ~ ('^' || (select auth.uid())::text || '/[0-9a-f]{32}\.pdf$')
  );

create policy project_questionnaires_read on storage.objects for select to authenticated
  using (
    bucket_id = 'project-questionnaires'
    and (
      split_part(name, '/', 1) = (select auth.uid())::text
      or exists (
        select 1 from public.projects p where p.questionnaire_file_path = storage.objects.name
      )
    )
  );

create policy project_questionnaires_delete_unattached on storage.objects for delete to authenticated
  using (
    bucket_id = 'project-questionnaires'
    and split_part(name, '/', 1) = (select auth.uid())::text
    and not exists (
      select 1 from public.projects p where p.questionnaire_file_path = storage.objects.name
    )
  );

create function evalink_private.validate_questionnaire_file()
returns trigger language plpgsql set search_path = '' as $$
begin
  if not exists (
    select 1 from storage.objects
    where bucket_id = 'project-questionnaires' and name = new.questionnaire_file_path
  ) then
    raise exception 'Upload the questionnaire PDF before creating the project';
  end if;
  return new;
end;
$$;

create trigger evalink_validate_questionnaire_file before insert on public.projects
for each row when (new.questionnaire_file_path is not null)
execute function evalink_private.validate_questionnaire_file();

revoke execute on function evalink_private.validate_questionnaire_file() from public, anon, authenticated;


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
  else
    expected_keys := array[]::text[];
  end if;

  if expected_keys is null
    or (select count(*) from jsonb_object_keys(new.scores)) <> cardinality(expected_keys)
    or exists (
      select 1 from unnest(expected_keys) as expected(key)
      where (new.scores ->> key) is null
        or jsonb_typeof(new.scores -> key) <> 'number'
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
