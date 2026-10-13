-- Applied remotely as the korean_memo_cloud_sync migration.
create table public.korean_memo_snapshots (
  user_id uuid primary key references auth.users(id) on delete cascade,
  revision bigint not null check (revision > 0),
  digest text not null check (digest ~ '^[a-f0-9]{64}$'),
  payload jsonb not null check (jsonb_typeof(payload) = 'object'),
  updated_at timestamptz not null default now()
);
alter table public.korean_memo_snapshots enable row level security;
revoke all on public.korean_memo_snapshots from anon;
grant select, insert, update on public.korean_memo_snapshots to authenticated;
create policy own_snapshot_read on public.korean_memo_snapshots
  for select to authenticated using ((select auth.uid()) = user_id);
create policy own_snapshot_insert on public.korean_memo_snapshots
  for insert to authenticated with check ((select auth.uid()) = user_id);
create policy own_snapshot_update on public.korean_memo_snapshots
  for update to authenticated using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

-- Compare-and-swap prevents two devices from silently overwriting one another.
-- Invoker privileges preserve the same ownership RLS as ordinary REST requests.
create function public.save_korean_memo_snapshot(
  p_expected_revision bigint, p_digest text, p_payload jsonb
) returns jsonb language plpgsql security invoker
set search_path = '' as $$
declare result jsonb;
begin
  if auth.uid() is null then raise exception 'LOGIN_REQUIRED' using errcode = '42501'; end if;
  if p_expected_revision is null or p_expected_revision < 0
     or p_digest is null or p_digest !~ '^[a-f0-9]{64}$'
     or p_payload is null or p_payload->>'format' is distinct from 'korean-memo-backup'
     or p_payload->>'version' is distinct from '1'
     or jsonb_typeof(p_payload->'tables') is distinct from 'object'
     or octet_length(p_payload::text) > 23 * 1024 * 1024 then
    raise exception 'INVALID_SNAPSHOT' using errcode = '22023';
  end if;
  if p_expected_revision = 0 then
    insert into public.korean_memo_snapshots (user_id, revision, digest, payload)
      values (auth.uid(), 1, p_digest, p_payload)
      on conflict (user_id) do nothing
      returning jsonb_build_object('revision', revision, 'digest', digest, 'updated_at', updated_at) into result;
  else
    update public.korean_memo_snapshots
      set revision = revision + 1, digest = p_digest, payload = p_payload, updated_at = now()
      where user_id = auth.uid() and revision = p_expected_revision
      returning jsonb_build_object('revision', revision, 'digest', digest, 'updated_at', updated_at) into result;
  end if;
  if result is null then raise exception 'SYNC_CONFLICT' using errcode = '40001'; end if;
  return result;
end;
$$;
revoke all on function public.save_korean_memo_snapshot(bigint, text, jsonb) from public, anon;
grant execute on function public.save_korean_memo_snapshot(bigint, text, jsonb) to authenticated;
