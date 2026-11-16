begin;

alter table public.profiles add column walkthrough_finished boolean not null default false;
update public.profiles set walkthrough_finished = true where onboarding_completed;
grant update (walkthrough_finished) on public.profiles to authenticated;

create function evalink_private.workspace_session_verified()
returns boolean language sql stable security definer set search_path = '' as $$
  select (select auth.uid()) is not null and (
    coalesce((select auth.jwt()) ->> 'aal', '') = 'aal2'
    or (
      not exists (
        select 1 from auth.mfa_factors f
        where f.user_id = (select auth.uid()) and f.status = 'verified'
      )
      and not exists (
        select 1 from auth.users u where u.id = (select auth.uid())
         and u.raw_app_meta_data ->> 'evalink_moderator' = 'true'
      )
    )
  );
$$;
revoke all on function evalink_private.workspace_session_verified() from public, anon, authenticated;
grant execute on function evalink_private.workspace_session_verified() to authenticated;

-- Restrictive policies preserve the existing ownership rules.
do $$
declare table_name text;
begin
  foreach table_name in array array[
    'profiles', 'rubrics', 'rubric_criteria', 'projects', 'review_assignments',
    'reviews', 'project_reports', 'saved_questionnaires', 'member_connections',
    'project_collaborators', 'project_review_rounds', 'review_messages',
    'workspace_notifications', 'project_revision_tasks', 'credential_requests',
    'checked_credentials', 'workspace_folders'
  ] loop
    execute format(
      'create policy verified_workspace_session on public.%I as restrictive to authenticated
        using ((select evalink_private.workspace_session_verified()))
        with check ((select evalink_private.workspace_session_verified()))',
      table_name
    );
  end loop;
end;
$$;

create policy verified_workspace_storage_session on storage.objects as restrictive to authenticated
using (bucket_id not in ('workspace-files', 'project-questionnaires') or (select evalink_private.workspace_session_verified()))
with check (bucket_id not in ('workspace-files', 'project-questionnaires') or (select evalink_private.workspace_session_verified()));

-- The existing public wrappers call private SECURITY DEFINER functions.
-- Gate the definer entry points too, so direct RPC calls cannot bypass RLS.
do $$
declare
  target regprocedure;
  definition text;
begin
  foreach target in array array[
    'evalink_private.submit_community_evaluation(uuid,jsonb,jsonb,text,jsonb)'::regprocedure,
    'evalink_private.update_project_questionnaire(uuid,jsonb)'::regprocedure,
    'evalink_private.send_review_reminder(uuid)'::regprocedure,
    'evalink_private.decide_credential(uuid,boolean,text)'::regprocedure
  ] loop
    definition := pg_get_functiondef(target);
    definition := replace(definition, E'begin\n', E'begin\n  if not evalink_private.workspace_session_verified() then\n    raise exception ''Verify your authenticator to continue.'' using errcode = ''42501'';\n  end if;\n');
    execute definition;
  end loop;
end;
$$;

create or replace function evalink_private.completed_review_count(p_evaluator uuid)
returns bigint language sql stable security definer set search_path = '' as $$
  select count(*) from public.review_assignments a
  where a.evaluator_id = p_evaluator and a.status = 'submitted'
  and evalink_private.workspace_session_verified()
  and exists (select 1 from public.profiles p where p.id = p_evaluator
    and (p.directory_visible or p.id = (select auth.uid())));
$$;

commit;
