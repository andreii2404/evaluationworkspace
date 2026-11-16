begin;

alter table public.review_assignments
  add column source text not null default 'invitation' check (source in ('invitation', 'community'));

create or replace function evalink_private.lock_project_access()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(new.project_id::text, 302));
  if tg_table_name = 'project_collaborators' then
    if not evalink_private.eligible_collaborator(new.project_id, new.member_id) then
      raise exception 'Choose a member who is not evaluating this project.' using errcode = '42501';
    end if;
  elsif new.source = 'community' then
    if new.evaluator_id is distinct from (select auth.uid())
      or evalink_private.project_is_team(new.project_id)
      or new.round_id is not null
      or new.status <> 'accepted'
      or not exists (
        select 1 from public.projects p where p.id = new.project_id and p.visibility = 'community'
          and num_nonnulls(p.questionnaire_form, p.rubric_id, p.custom_questions) > 0
      ) then
      raise exception 'This community evaluation is unavailable.' using errcode = '42501';
    end if;
  elsif not evalink_private.eligible_reviewer(new.project_id, new.evaluator_id) then
    raise exception 'Choose an independent, directory-visible evaluator.' using errcode = '42501';
  end if;
  return new;
end;
$$;

create or replace function evalink_private.send_workspace_notification()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  assignment public.review_assignments%rowtype;
begin
  if tg_table_name = 'project_collaborators' then
    insert into public.workspace_notifications (recipient_id, project_id, kind)
    values (new.member_id, new.project_id, 'team');
  elsif tg_table_name = 'review_assignments' then
    if tg_op = 'INSERT' then
      if new.source = 'invitation' then
        insert into public.workspace_notifications (recipient_id, project_id, assignment_id, kind)
        values (new.evaluator_id, new.project_id, new.id, 'invited');
      end if;
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

create function evalink_private.submit_community_evaluation(
  p_project uuid, p_form jsonb, p_scores jsonb, p_feedback text, p_details jsonb
)
returns void language plpgsql security definer set search_path = '' as $$
declare
  actor uuid := (select auth.uid());
  project public.projects%rowtype;
  assignment public.review_assignments%rowtype;
begin
  if actor is null then raise exception 'Sign in to evaluate this project.' using errcode = '42501'; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_project::text, 302));
  select * into project from public.projects where id = p_project for share;
  if not found or project.visibility <> 'community'
    or num_nonnulls(project.questionnaire_form, project.rubric_id, project.custom_questions) = 0
    or evalink_private.project_is_team(p_project) then
    raise exception 'This community evaluation is unavailable.' using errcode = '42501';
  end if;
  if project.questionnaire_form is distinct from p_form then
    raise exception 'The questionnaire changed. Reopen the project to answer the current version.';
  end if;

  select * into assignment from public.review_assignments a
    where a.project_id = p_project and a.evaluator_id = actor and a.round_id is null for update;
  if found then
    if assignment.status = 'submitted' then
      raise exception 'You already submitted an evaluation for this project.';
    elsif assignment.status = 'declined' then
      raise exception 'You already declined this project’s review invitation.';
    elsif assignment.status = 'invited' then
      update public.review_assignments set status = 'accepted' where id = assignment.id;
    end if;
  else
    insert into public.review_assignments (project_id, creator_id, evaluator_id, status, source, responded_at)
    values (p_project, project.creator_id, actor, 'accepted', 'community', now())
    returning * into assignment;
  end if;

  insert into public.reviews (assignment_id, scores, feedback, no_conflict, respondent_details)
  values (assignment.id, p_scores, p_feedback, true, p_details);
end;
$$;

create function public.submit_community_evaluation(
  p_project uuid, p_form jsonb, p_scores jsonb, p_feedback text, p_details jsonb
)
returns void language sql security invoker set search_path = '' as $$
  select evalink_private.submit_community_evaluation(p_project, p_form, p_scores, p_feedback, p_details);
$$;

create function evalink_private.update_project_questionnaire(p_project uuid, p_form jsonb)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not evalink_private.project_is_owner(p_project) then
    raise exception 'Only the project owner can edit its questionnaire.' using errcode = '42501';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_project::text, 302));
  if exists (select 1 from public.review_assignments where project_id = p_project) then
    raise exception 'This questionnaire is locked because review invitations or responses already exist.';
  end if;
  if p_form is null or not evalink_private.valid_questionnaire_form(p_form) then
    raise exception 'Add a valid questionnaire with at least one question.';
  end if;
  update public.projects set questionnaire_form = p_form, rubric_id = null, custom_questions = null,
    questionnaire_file_path = null, questionnaire_file_name = null, questionnaire_url = null
  where id = p_project and creator_id = (select auth.uid());
  if not found then raise exception 'This project is unavailable.' using errcode = '42501'; end if;
end;
$$;

create function public.update_project_questionnaire(p_project uuid, p_form jsonb)
returns void language sql security invoker set search_path = '' as $$
  select evalink_private.update_project_questionnaire(p_project, p_form);
$$;

revoke all on function
  evalink_private.submit_community_evaluation(uuid, jsonb, jsonb, text, jsonb),
  public.submit_community_evaluation(uuid, jsonb, jsonb, text, jsonb),
  evalink_private.update_project_questionnaire(uuid, jsonb),
  public.update_project_questionnaire(uuid, jsonb)
from public, anon, authenticated;
grant execute on function
  evalink_private.submit_community_evaluation(uuid, jsonb, jsonb, text, jsonb),
  public.submit_community_evaluation(uuid, jsonb, jsonb, text, jsonb),
  evalink_private.update_project_questionnaire(uuid, jsonb),
  public.update_project_questionnaire(uuid, jsonb)
to authenticated;

commit;
