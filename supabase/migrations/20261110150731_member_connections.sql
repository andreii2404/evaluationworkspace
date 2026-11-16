begin;

create table public.member_connections (
  id uuid primary key default gen_random_uuid(),
  requester_id uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  recipient_id uuid not null references public.profiles(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending', 'accepted')),
  created_at timestamptz not null default now(),
  check (requester_id <> recipient_id)
);

create unique index member_connections_pair_idx on public.member_connections (
  least(requester_id, recipient_id), greatest(requester_id, recipient_id)
);
create index member_connections_requester_idx on public.member_connections (requester_id);
create index member_connections_recipient_idx on public.member_connections (recipient_id);

alter table public.member_connections enable row level security;
revoke all on public.member_connections from public, anon, authenticated;
grant select, delete on public.member_connections to authenticated;
grant insert (recipient_id), update (status) on public.member_connections to authenticated;

create policy connections_read_participants on public.member_connections
for select to authenticated using (
  (select auth.uid()) in (requester_id, recipient_id)
);

create policy connections_send_as_self on public.member_connections
for insert to authenticated with check (
  requester_id = (select auth.uid()) and status = 'pending'
  and exists (select 1 from public.profiles p where p.id = requester_id and p.directory_visible)
  and exists (select 1 from public.profiles p where p.id = recipient_id and p.directory_visible)
);

create policy connections_accept_as_recipient on public.member_connections
for update to authenticated
using (recipient_id = (select auth.uid()) and status = 'pending')
with check (recipient_id = (select auth.uid()) and status = 'accepted');

create policy connections_remove_as_participant on public.member_connections
for delete to authenticated using (
  (select auth.uid()) in (requester_id, recipient_id)
);

commit;
