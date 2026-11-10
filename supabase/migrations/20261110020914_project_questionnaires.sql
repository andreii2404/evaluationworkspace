begin;

alter table public.projects
  add column audience text check (char_length(audience) <= 250),
  add column test_instructions text check (char_length(test_instructions) <= 1600),
  add column questionnaire_url text check (
    char_length(questionnaire_url) <= 500 and
    questionnaire_url ~* '^https://[^/@?#[:space:]]+([/?#][^[:space:]]*)?$'
  ),
  add column custom_questions jsonb,
  alter column rubric_id drop not null,
  drop constraint projects_category_check,
  add constraint projects_category_check check (
    category in ('Website', 'Mobile app', 'Research', 'Prototype', 'Game', 'Creative work', 'Other')
  ),
  add constraint projects_questionnaire_check check (
    (rubric_id is not null or custom_questions is not null or questionnaire_url is not null) and
    (rubric_id is null or custom_questions is null)
  );

grant insert (audience, test_instructions, questionnaire_url, custom_questions)
  on public.projects to authenticated;

create function evalink_private.validate_project_questionnaire()
returns trigger language plpgsql set search_path = '' as $$
begin
  if new.artifact_url is null or
    new.artifact_url !~ '^https://[^/@?#[:space:]]+([/?#][^[:space:]]*)?$' then
    raise exception 'A direct HTTPS project link is required';
  end if;
  if new.custom_questions is not null then
    if jsonb_typeof(new.custom_questions) <> 'array' then
      raise exception 'Custom questions must be an array';
    end if;
    if jsonb_array_length(new.custom_questions) not between 1 and 24
      or exists (
        select 1 from jsonb_array_elements(new.custom_questions) as items(item)
        where jsonb_typeof(item) <> 'string'
          or char_length(item #>> '{}') > 240
          or item #>> '{}' !~ '[^[:space:]]'
      ) then
      raise exception 'Add 1 to 24 questions, each between 1 and 240 characters';
    end if;
  end if;
  return new;
end;
$$;

create trigger evalink_validate_project_questionnaire
before insert on public.projects
for each row execute function evalink_private.validate_project_questionnaire();

revoke execute on function evalink_private.validate_project_questionnaire() from public, anon, authenticated;

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
  elsif project.questionnaire_url is not null then
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

insert into public.rubrics (id, name, version) values
  ('website-iso25010-v1', 'Website quality · ISO/IEC 25010:2023-informed', 1),
  ('mobile-mars-v1', 'Mobile app quality · MARS-informed', 1);

insert into public.rubric_criteria (rubric_id, criterion_key, position, label, prompt) values
  ('website-iso25010-v1', 'functional', 1, 'Functional suitability', 'Can you complete the requested website tasks and get the expected results?'),
  ('website-iso25010-v1', 'performance', 2, 'Performance efficiency', 'Do pages load and respond at an acceptable speed on your test device and connection?'),
  ('website-iso25010-v1', 'compatibility', 3, 'Compatibility', 'Does the website behave as expected in the supported browsers or integrations you can test?'),
  ('website-iso25010-v1', 'interaction', 4, 'Interaction capability', 'Can you find controls, understand what to do next, and use the site with your usual access tools?'),
  ('website-iso25010-v1', 'reliability', 5, 'Reliability', 'Do repeated tasks give consistent results, and can you recover from errors or interrupted actions?'),
  ('website-iso25010-v1', 'security', 6, 'Security', 'Based on authorized tests, are sensitive information and actions restricted to the expected users?'),
  ('website-iso25010-v1', 'maintainability', 7, 'Maintainability', 'From the available code, docs, or demonstration, how readily could a team isolate and verify a change?'),
  ('website-iso25010-v1', 'flexibility', 8, 'Flexibility', 'Does the website adapt to changes in screen size, supported settings, or usage conditions you can test?'),
  ('website-iso25010-v1', 'safety', 9, 'Safety', 'Does the site guard against foreseeable harm, such as accidental destructive actions or misleading instructions?'),
  ('mobile-mars-v1', 'engagement', 1, 'Engagement', 'Does the app give its intended users a clear reason to keep using it after trying the main task?'),
  ('mobile-mars-v1', 'functionality', 2, 'Functionality', 'Do the main tasks run reliably, with predictable navigation and touch controls?'),
  ('mobile-mars-v1', 'aesthetics', 3, 'Visual design', 'Are the layout, typography, and visuals clear and consistent on the device you tested?'),
  ('mobile-mars-v1', 'information', 4, 'Information quality', 'Is the app''s content understandable, relevant, and supported by sources where needed?'),
  ('mobile-mars-v1', 'overall', 5, 'Overall impression', 'After testing the app, how useful would it be to someone in its intended audience?');

commit;
