begin;

create schema professional_private;
revoke all on schema professional_private from public, anon, authenticated;
grant usage on schema professional_private to authenticated;

create table public.professional_services (
  evaluator_id uuid primary key default auth.uid() references public.profiles(id) on delete cascade,
  summary text not null check (length(btrim(summary)) between 15 and 600),
  qualifications text not null check (length(btrim(qualifications)) between 10 and 450),
  base_price integer not null check (base_price between 10000 and 10000000),
  turnaround_days integer not null check (turnaround_days between 1 and 30),
  available boolean not null default false,
  approved_at timestamptz,
  updated_at timestamptz not null default now()
);

create table public.professional_orders (
  id uuid primary key default gen_random_uuid(),
  buyer_id uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  evaluator_id uuid not null references public.profiles(id) on delete cascade,
  project_id uuid references public.projects(id) on delete set null,
  title text not null check (length(btrim(title)) between 3 and 100),
  brief text not null check (length(btrim(brief)) between 20 and 1800),
  draft_version text not null check (length(btrim(draft_version)) between 1 and 60),
  mode text not null default 'sandbox' check (mode = 'sandbox'),
  currency text not null default 'PHP' check (currency = 'PHP'),
  status text not null default 'requested' check (status in (
    'requested', 'quoted', 'in_progress', 'delivered', 'clarification',
    'disputed', 'completed', 'refunded', 'cancelled', 'declined'
  )),
  payment_status text not null default 'unfunded' check (payment_status in (
    'unfunded', 'test_funded', 'test_refunded', 'test_released'
  )),
  amount integer check (amount between 10000 and 10000000),
  platform_fee integer generated always as (amount * 12 / 100) stored,
  scope text check (length(btrim(scope)) between 20 and 2000),
  turnaround_days integer check (turnaround_days between 1 and 30),
  quote_expires_at timestamptz,
  funded_at timestamptz,
  due_at timestamptz,
  delivered_at timestamptz,
  closed_at timestamptz,
  findings text check (length(btrim(findings)) between 30 and 6000),
  clarification text check (length(btrim(clarification)) between 10 and 2000),
  clarification_reply text check (length(btrim(clarification_reply)) between 10 and 3000),
  dispute_reason text check (length(btrim(dispute_reason)) between 10 and 2000),
  resolution text check (length(btrim(resolution)) between 10 and 2000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (buyer_id <> evaluator_id)
);

create index professional_orders_buyer on public.professional_orders (buyer_id, updated_at desc);
create index professional_orders_evaluator on public.professional_orders (evaluator_id, updated_at desc);
create index professional_orders_disputes on public.professional_orders (updated_at) where status = 'disputed';

create table public.professional_order_events (
  id bigint generated always as identity primary key,
  order_id uuid not null references public.professional_orders(id) on delete cascade,
  action text not null,
  actor_id uuid references public.profiles(id) on delete set null,
  amount integer,
  created_at timestamptz not null default now()
);
create index professional_order_events_order on public.professional_order_events (order_id, id);

create table public.professional_revision_items (
  id bigint generated always as identity primary key,
  order_id uuid not null references public.professional_orders(id) on delete cascade,
  description text not null check (length(btrim(description)) between 1 and 240),
  done boolean not null default false
);
create index professional_revision_items_order on public.professional_revision_items (order_id, id);

alter table public.professional_services enable row level security;
alter table public.professional_orders enable row level security;
alter table public.professional_order_events enable row level security;
alter table public.professional_revision_items enable row level security;

revoke all on public.professional_services, public.professional_orders,
  public.professional_order_events, public.professional_revision_items from public, anon, authenticated;
grant select on public.professional_services, public.professional_orders,
  public.professional_order_events, public.professional_revision_items to authenticated;
grant insert (summary, qualifications, base_price, turnaround_days, available)
  on public.professional_services to authenticated;
grant update (summary, qualifications, base_price, turnaround_days, available)
  on public.professional_services to authenticated;
grant insert (evaluator_id, project_id, title, brief, draft_version)
  on public.professional_orders to authenticated;
grant update (done) on public.professional_revision_items to authenticated;

create policy professional_services_read on public.professional_services for select to authenticated
using (
  evaluator_id = (select auth.uid())
  or (available and approved_at is not null and exists (
    select 1 from public.profiles p
    where p.id = evaluator_id and p.directory_visible and p.email_confirmed
  ))
  or (select auth.jwt()) -> 'app_metadata' ->> 'evalink_moderator' = 'true'
);

create policy professional_services_add on public.professional_services for insert to authenticated
with check (
  evaluator_id = (select auth.uid())
  and exists (select 1 from public.profiles p where p.id = evaluator_id and p.email_confirmed)
);
create policy professional_services_edit on public.professional_services for update to authenticated
using (evaluator_id = (select auth.uid()))
with check (evaluator_id = (select auth.uid()));

create policy professional_orders_read on public.professional_orders for select to authenticated
using (
  buyer_id = (select auth.uid()) or evaluator_id = (select auth.uid())
  or (dispute_reason is not null and (select auth.jwt()) -> 'app_metadata' ->> 'evalink_moderator' = 'true')
);

create policy professional_orders_request on public.professional_orders for insert to authenticated
with check (
  buyer_id = (select auth.uid())
  and exists (select 1 from public.profiles p where p.id = buyer_id and p.email_confirmed)
  and exists (
    select 1 from public.professional_services s
    where s.evaluator_id = professional_orders.evaluator_id and s.available and s.approved_at is not null
  )
  and exists (
    select 1 from public.profiles p
    where p.id = professional_orders.evaluator_id and p.directory_visible and p.email_confirmed
  )
  and (project_id is null or exists (
    select 1 from public.projects p where p.id = project_id and p.creator_id = (select auth.uid())
  ))
);

create policy professional_events_read on public.professional_order_events for select to authenticated
using (exists (select 1 from public.professional_orders o where o.id = order_id));

create policy professional_revision_items_read on public.professional_revision_items for select to authenticated
using (exists (select 1 from public.professional_orders o where o.id = order_id and o.buyer_id = (select auth.uid())));
create policy professional_revision_items_edit on public.professional_revision_items for update to authenticated
using (exists (select 1 from public.professional_orders o where o.id = order_id and o.buyer_id = (select auth.uid())))
with check (exists (select 1 from public.professional_orders o where o.id = order_id and o.buyer_id = (select auth.uid())));

create function professional_private.mark_listing_edit()
returns trigger language plpgsql set search_path = '' as $$
begin
  if old.summary is distinct from new.summary or old.qualifications is distinct from new.qualifications then
    new.approved_at := null;
  end if;
  new.updated_at := clock_timestamp();
  return new;
end;
$$;
revoke all on function professional_private.mark_listing_edit() from public, anon, authenticated;
create trigger mark_professional_listing_edit before update on public.professional_services
for each row execute function professional_private.mark_listing_edit();

create function professional_private.record_request()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.professional_order_events (order_id, action, actor_id)
  values (new.id, 'request', new.buyer_id);
  return new;
end;
$$;
revoke all on function professional_private.record_request() from public, anon, authenticated;
create trigger record_professional_request after insert on public.professional_orders
for each row execute function professional_private.record_request();

create function professional_private.moderate_listing(p_evaluator uuid, p_approve boolean, p_version timestamptz)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if coalesce((select auth.jwt()) -> 'app_metadata' ->> 'evalink_moderator', '') <> 'true'
    or (select auth.uid()) is null or p_evaluator = (select auth.uid()) then
    raise exception 'Only another moderator can review this listing.' using errcode = '42501';
  end if;
  update public.professional_services
  set approved_at = case when p_approve then now() end
  where evaluator_id = p_evaluator and updated_at = p_version;
  if not found then
    raise exception 'This listing changed. Refresh and review the current version.';
  end if;
end;
$$;

create function public.moderate_professional_listing(p_evaluator uuid, p_approve boolean, p_version timestamptz)
returns void language sql security invoker set search_path = '' as $$
  select professional_private.moderate_listing(p_evaluator, p_approve, p_version);
$$;

create function professional_private.advance_order(
  p_order uuid,
  p_action text,
  p_version timestamptz,
  p_text text,
  p_amount integer,
  p_days integer,
  p_items text[],
  p_agreed boolean
)
returns void language plpgsql security definer set search_path = '' as $$
declare
  active public.professional_orders%rowtype;
  actor uuid := (select auth.uid());
  buyer boolean;
  evaluator boolean;
  moderator boolean := coalesce((select auth.jwt()) -> 'app_metadata' ->> 'evalink_moderator', '') = 'true';
  body text := btrim(p_text);
begin
  if actor is null then
    raise exception 'Sign in to manage a review.' using errcode = '42501';
  end if;
  select * into active from public.professional_orders o
  where o.id = p_order and (
    o.buyer_id = actor or o.evaluator_id = actor or (moderator and o.status = 'disputed')
  ) for update;
  if not found then
    raise exception 'Review unavailable.' using errcode = '42501';
  end if;
  if active.updated_at is distinct from p_version then
    raise exception 'This review changed. Refresh and try again.';
  end if;

  buyer := actor = active.buyer_id;
  evaluator := actor = active.evaluator_id;
  case
    when p_action = 'quote' and evaluator and active.status = 'requested' then
      if p_agreed is not true then
        raise exception 'Confirm that you can provide an independent review.';
      end if;
      if p_amount is null or p_days is null or body is null or p_amount not between 10000 and 10000000
        or p_days not between 1 and 30 or length(body) not between 20 and 2000 then
        raise exception 'Enter a price, turnaround, and clear scope.';
      end if;
      update public.professional_orders set status = 'quoted', amount = p_amount,
        scope = body, turnaround_days = p_days, quote_expires_at = now() + interval '7 days', updated_at = clock_timestamp()
      where id = active.id;
    when p_action = 'decline' and evaluator and active.status in ('requested', 'quoted') then
      update public.professional_orders set status = 'declined', closed_at = now(), updated_at = clock_timestamp()
      where id = active.id;
    when p_action = 'cancel' and buyer and active.status in ('requested', 'quoted') then
      update public.professional_orders set status = 'cancelled', closed_at = now(), updated_at = clock_timestamp()
      where id = active.id;
    when p_action = 'fund_test' and buyer and active.status = 'quoted' then
      if p_agreed is not true then
        raise exception 'Accept the quote and confirm that you can share the draft.';
      end if;
      if active.quote_expires_at <= now() then
        raise exception 'This quote expired. Cancel it and request a new review.';
      end if;
      if not exists (
        select 1 from storage.objects f
        where f.bucket_id = 'professional-review-files' and f.name = active.id::text || '/draft.pdf'
      ) then
        raise exception 'Upload the draft PDF before confirming the quote.';
      end if;
      update public.professional_orders set status = 'in_progress', payment_status = 'test_funded',
        funded_at = now(), due_at = now() + make_interval(days => active.turnaround_days), updated_at = clock_timestamp()
      where id = active.id;
    when p_action = 'deliver' and evaluator and active.status = 'in_progress' then
      if body is null or length(body) not between 30 and 6000
        or coalesce(cardinality(p_items), 0) not between 1 and 12
        or exists (select 1 from unnest(p_items) item where item is null or length(btrim(item)) not between 1 and 240) then
        raise exception 'Add the review findings and 1 to 12 specific next steps.';
      end if;
      insert into public.professional_revision_items (order_id, description)
      select active.id, btrim(item) from unnest(p_items) item;
      update public.professional_orders set status = 'delivered', findings = body,
        delivered_at = now(), updated_at = clock_timestamp() where id = active.id;
    when p_action = 'clarify' and buyer and active.status = 'delivered' and active.clarification is null then
      if body is null or length(body) not between 10 and 2000 then
        raise exception 'Describe what you need clarified.';
      end if;
      update public.professional_orders set status = 'clarification', clarification = body, updated_at = clock_timestamp()
      where id = active.id;
    when p_action = 'respond' and evaluator and active.status = 'clarification' then
      if body is null or length(body) not between 10 and 3000 then
        raise exception 'Add a response to the clarification.';
      end if;
      update public.professional_orders set status = 'delivered', clarification_reply = body, updated_at = clock_timestamp()
      where id = active.id;
    when p_action = 'accept' and buyer and active.status = 'delivered' then
      update public.professional_orders set status = 'completed', payment_status = 'test_released',
        closed_at = now(), updated_at = clock_timestamp() where id = active.id;
    when p_action = 'dispute' and (buyer or evaluator)
      and active.status in ('in_progress', 'delivered', 'clarification') then
      if body is null or length(body) not between 10 and 2000 then
        raise exception 'Describe the issue for the moderator.';
      end if;
      update public.professional_orders set status = 'disputed', dispute_reason = body, updated_at = clock_timestamp()
      where id = active.id;
    when p_action in ('resolve_refund', 'resolve_release') and moderator and not buyer and not evaluator
      and active.status = 'disputed' then
      if body is null or length(body) not between 10 and 2000 then
        raise exception 'Record the reason for your decision.';
      end if;
      update public.professional_orders set
        status = case p_action when 'resolve_refund' then 'refunded' else 'completed' end,
        payment_status = case p_action when 'resolve_refund' then 'test_refunded' else 'test_released' end,
        resolution = body, closed_at = now(), updated_at = clock_timestamp() where id = active.id;
    else
      raise exception 'This action is unavailable at the current stage.' using errcode = '42501';
  end case;

  insert into public.professional_order_events (order_id, action, actor_id, amount)
  values (active.id, p_action, actor, case when p_action = 'quote' then p_amount
    when p_action in ('fund_test', 'accept', 'resolve_refund', 'resolve_release') then active.amount end);
end;
$$;

create function public.advance_professional_order(
  p_order uuid,
  p_action text,
  p_version timestamptz,
  p_text text default null,
  p_amount integer default null,
  p_days integer default null,
  p_items text[] default null,
  p_agreed boolean default false
)
returns void language sql security invoker set search_path = '' as $$
  select professional_private.advance_order(p_order, p_action, p_version, p_text, p_amount, p_days, p_items, p_agreed);
$$;

revoke all on function professional_private.moderate_listing(uuid, boolean, timestamptz),
  public.moderate_professional_listing(uuid, boolean, timestamptz),
  professional_private.advance_order(uuid, text, timestamptz, text, integer, integer, text[], boolean),
  public.advance_professional_order(uuid, text, timestamptz, text, integer, integer, text[], boolean)
  from public, anon, authenticated;
grant execute on function professional_private.moderate_listing(uuid, boolean, timestamptz),
  public.moderate_professional_listing(uuid, boolean, timestamptz),
  professional_private.advance_order(uuid, text, timestamptz, text, integer, integer, text[], boolean),
  public.advance_professional_order(uuid, text, timestamptz, text, integer, integer, text[], boolean) to authenticated;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('professional-review-files', 'professional-review-files', false, 5242880, array['application/pdf']);

create policy professional_draft_read on storage.objects for select to authenticated
using (bucket_id = 'professional-review-files' and exists (
  select 1 from public.professional_orders o where name = o.id::text || '/draft.pdf'
  and (o.buyer_id = (select auth.uid())
    or (o.evaluator_id = (select auth.uid()) and o.status in ('in_progress', 'delivered', 'clarification')))
));

create policy professional_draft_upload on storage.objects for insert to authenticated
with check (bucket_id = 'professional-review-files' and exists (
  select 1 from public.professional_orders o where name = o.id::text || '/draft.pdf'
  and o.buyer_id = (select auth.uid()) and o.status = 'quoted' and o.quote_expires_at > now()
));

create policy professional_draft_remove on storage.objects for delete to authenticated
using (bucket_id = 'professional-review-files' and exists (
  select 1 from public.professional_orders o where name = o.id::text || '/draft.pdf'
  and o.buyer_id = (select auth.uid()) and o.status in ('cancelled', 'declined', 'completed', 'refunded')
));

commit;
