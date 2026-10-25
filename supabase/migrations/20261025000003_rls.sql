-- 심이베 캘린더 3/4: 접근 권한 (RLS)
-- 기준 문서: docs/03-design/ERD및테이블정의서.md 4장
-- 표에 없는 동작은 모두 막는다. 테이블 권한(grant)은 바꿀 수 있는 컬럼까지 좁히고,
-- 행 단위 정책(policy)으로 "내 데이터"만 허용한다.

alter table public.members enable row level security;
alter table public.connections enable row level security;
alter table public.events enable row level security;
alter table public.event_participants enable row level security;
alter table public.categories enable row level security;
alter table public.notifications enable row level security;
alter table public.device_tokens enable row level security;

-- Supabase가 기본으로 주는 전체 권한을 거두고 필요한 것만 다시 준다
revoke all on public.members, public.connections, public.events, public.event_participants,
  public.categories, public.notifications, public.device_tokens
  from anon, authenticated;

------------------------------------------------------------
-- members: 조회는 나·연결·요청·같은 일정 참여자, 수정은 내 이름만
------------------------------------------------------------
grant select on public.members to authenticated;
grant update (name) on public.members to authenticated;

create policy members_select on public.members
  for select to authenticated
  using (public.can_see_member(id));

create policy members_update on public.members
  for update to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

------------------------------------------------------------
-- connections: 내가 요청했거나 받은 행
------------------------------------------------------------
grant select, delete on public.connections to authenticated;
grant insert (requester_id, addressee_id) on public.connections to authenticated;
grant update (status) on public.connections to authenticated;

create policy connections_select on public.connections
  for select to authenticated
  using ((select auth.uid()) in (requester_id, addressee_id));

create policy connections_insert on public.connections
  for insert to authenticated
  with check (requester_id = (select auth.uid()) and status = 'pending');

-- 수락은 요청받은 사람만 (pending -> accepted 검사는 트리거)
create policy connections_update on public.connections
  for update to authenticated
  using (addressee_id = (select auth.uid()))
  with check (addressee_id = (select auth.uid()));

-- 거절, 요청 취소, 연결 해제
create policy connections_delete on public.connections
  for delete to authenticated
  using ((select auth.uid()) in (requester_id, addressee_id));

------------------------------------------------------------
-- events: 참여 중인 일정만 조회·수정. 추가는 create_event, 삭제는 서버만
------------------------------------------------------------
grant select on public.events to authenticated;
grant update (
  title, location, memo, time_type, start_date, end_date, start_at, end_at,
  time_zone, repeat_type, repeat_weekdays, repeat_until
) on public.events to authenticated;

create policy events_select on public.events
  for select to authenticated
  using (public.is_event_participant(id));

create policy events_update on public.events
  for update to authenticated
  using (public.is_event_participant(id))
  with check (public.is_event_participant(id));

------------------------------------------------------------
-- event_participants: 내 행만. 분류·미리 알림 수정과 빼기(삭제)
------------------------------------------------------------
grant select, delete on public.event_participants to authenticated;
grant update (category_id, reminder) on public.event_participants to authenticated;

create policy participants_select on public.event_participants
  for select to authenticated
  using (user_id = (select auth.uid()));

create policy participants_update on public.event_participants
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

create policy participants_delete on public.event_participants
  for delete to authenticated
  using (user_id = (select auth.uid()));

------------------------------------------------------------
-- categories: 내 분류. 기본 분류 표시(system_key)는 앱이 바꿀 수 없다
------------------------------------------------------------
grant select, delete on public.categories to authenticated;
grant insert (user_id, name, color, sort_order) on public.categories to authenticated;
grant update (name, color, sort_order) on public.categories to authenticated;

create policy categories_select on public.categories
  for select to authenticated
  using (user_id = (select auth.uid()));

create policy categories_insert on public.categories
  for insert to authenticated
  with check (user_id = (select auth.uid()));

create policy categories_update on public.categories
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

-- "그 외" 삭제 차단은 트리거가 한다
create policy categories_delete on public.categories
  for delete to authenticated
  using (user_id = (select auth.uid()));

------------------------------------------------------------
-- notifications: 내 알림 조회, 읽음 처리만
------------------------------------------------------------
grant select on public.notifications to authenticated;
grant update (is_read) on public.notifications to authenticated;

create policy notifications_select on public.notifications
  for select to authenticated
  using (user_id = (select auth.uid()));

create policy notifications_update on public.notifications
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

------------------------------------------------------------
-- device_tokens: 내 토큰 조회·삭제 (등록은 register_device_token)
------------------------------------------------------------
grant select, delete on public.device_tokens to authenticated;

create policy device_tokens_select on public.device_tokens
  for select to authenticated
  using (user_id = (select auth.uid()));

create policy device_tokens_delete on public.device_tokens
  for delete to authenticated
  using (user_id = (select auth.uid()));
