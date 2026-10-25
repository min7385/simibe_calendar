-- 심이베 캘린더 2/4: 서버 함수(RPC)와 자동 처리(트리거)
-- 기준 문서: docs/03-design/ERD및테이블정의서.md 5장

------------------------------------------------------------
-- 공통: 수정 시각
------------------------------------------------------------
create function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger members_set_updated_at
  before update on public.members
  for each row execute function public.set_updated_at();

------------------------------------------------------------
-- 가입: 회원 정보와 기본 분류 5개 만들기 (REQ-AUTH-001, REQ-CAT-001)
-- 앱은 signUp의 data에 handle, name을 넘긴다
------------------------------------------------------------
create function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_handle text := lower(btrim(new.raw_user_meta_data ->> 'handle'));
  v_name text := btrim(new.raw_user_meta_data ->> 'name');
begin
  if v_handle is null or v_name is null then
    raise exception 'handle and name are required in sign-up metadata';
  end if;

  insert into public.members (id, handle, name)
  values (new.id, v_handle, v_name);

  insert into public.categories (user_id, name, color, sort_order, system_key)
  values
    (new.id, '공유받은 일정', '#7E57C2', 1, 'shared'),
    (new.id, '개인',         '#42A5F5', 2, null),
    (new.id, '직장',         '#EF6C00', 3, null),
    (new.id, '가족',         '#43A047', 4, null),
    (new.id, '그 외',        '#9E9E9E', 5, 'etc');

  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

------------------------------------------------------------
-- 권한 판단 도우미 (RLS와 함수에서 사용)
------------------------------------------------------------
-- 나와 연결됐는지 (accepted)
create function public.is_connected_with(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.connections c
    where c.status = 'accepted'
      and ((c.requester_id = auth.uid() and c.addressee_id = p_user_id)
        or (c.addressee_id = auth.uid() and c.requester_id = p_user_id))
  );
$$;

-- 내가 이 사람의 이름과 고유 아이디를 볼 수 있는지
-- (연결됐거나 요청을 주고받았거나, 같은 일정에 참여 중)
create function public.can_see_member(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select p_user_id = auth.uid()
    or exists (
      select 1 from public.connections c
      where (c.requester_id = auth.uid() and c.addressee_id = p_user_id)
         or (c.addressee_id = auth.uid() and c.requester_id = p_user_id)
    )
    or exists (
      select 1
      from public.event_participants me
      join public.event_participants other on other.event_id = me.event_id
      where me.user_id = auth.uid() and other.user_id = p_user_id
    );
$$;

-- 내가 이 일정에 참여 중인지
create function public.is_event_participant(p_event_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.event_participants ep
    where ep.event_id = p_event_id and ep.user_id = auth.uid()
  );
$$;

------------------------------------------------------------
-- 회원
------------------------------------------------------------
-- 고유 아이디 사용 가능 여부 (REQ-AUTH-004). 가입 전이라 로그인 없이 호출
create function public.is_handle_available(p_handle text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select not exists (
    select 1 from public.members m where m.handle = lower(btrim(p_handle))
  );
$$;

-- 고유 아이디로 사용자 찾기 (REQ-CONN-001)
-- connection_status: self, connected, sent(내가 요청), received(상대가 요청), none
create function public.find_user_by_handle(p_handle text)
returns table (id uuid, handle text, name text, connection_status text)
language sql
stable
security definer
set search_path = ''
as $$
  select
    m.id,
    m.handle,
    m.name,
    case
      when m.id = auth.uid() then 'self'
      when c.status = 'accepted' then 'connected'
      when c.requester_id = auth.uid() then 'sent'
      when c.addressee_id = auth.uid() then 'received'
      else 'none'
    end
  from public.members m
  left join public.connections c
    on (c.requester_id = auth.uid() and c.addressee_id = m.id)
    or (c.addressee_id = auth.uid() and c.requester_id = m.id)
  where m.handle = lower(btrim(p_handle))
    and auth.uid() is not null;
$$;

------------------------------------------------------------
-- 연결
------------------------------------------------------------
-- 연결 요청 (REQ-CONN-002). 상대가 보낸 요청이 있으면 그 요청을 수락한다
-- 반환: requested, accepted, already_connected, already_requested
create function public.send_connection_request(p_user_id uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me uuid := auth.uid();
  v_conn public.connections;
begin
  if v_me is null then
    raise exception 'not authenticated';
  end if;
  if p_user_id = v_me then
    raise exception 'cannot connect to yourself';
  end if;

  select * into v_conn from public.connections c
  where (c.requester_id = v_me and c.addressee_id = p_user_id)
     or (c.addressee_id = v_me and c.requester_id = p_user_id);

  if not found then
    insert into public.connections (requester_id, addressee_id) values (v_me, p_user_id);
    return 'requested';
  elsif v_conn.status = 'accepted' then
    return 'already_connected';
  elsif v_conn.requester_id = v_me then
    return 'already_requested';
  else
    update public.connections set status = 'accepted' where id = v_conn.id;
    return 'accepted';
  end if;
end;
$$;

-- 수락은 pending -> accepted만 허용하고 수락 시각을 기록한다
create function public.connections_before_update()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if old.status <> 'pending' or new.status <> 'accepted' then
    raise exception 'only pending requests can be accepted';
  end if;
  new.accepted_at := now();
  return new;
end;
$$;

create trigger connections_before_update
  before update on public.connections
  for each row execute function public.connections_before_update();

------------------------------------------------------------
-- 분류
------------------------------------------------------------
-- 분류 삭제 직전: "그 외"는 막고, 일정은 "그 외"로 옮긴다 (REQ-CAT-005, 006)
create function public.categories_before_delete()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_etc uuid;
begin
  -- 회원 탈퇴로 함께 지워지는 중이면 그대로 둔다
  if not exists (select 1 from public.members m where m.id = old.user_id) then
    return old;
  end if;

  if old.system_key = 'etc' then
    raise exception 'the "etc" category cannot be deleted';
  end if;

  select c.id into v_etc from public.categories c
  where c.user_id = old.user_id and c.system_key = 'etc';

  update public.event_participants set category_id = v_etc
  where category_id = old.id;

  return old;
end;
$$;

create trigger categories_before_delete
  before delete on public.categories
  for each row execute function public.categories_before_delete();

------------------------------------------------------------
-- 일정 참여자
------------------------------------------------------------
-- 추가·수정 직전: 분류 기본값, 분류 주인, 미리 알림 값 검사
create function public.participants_before_write()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_time_type text;
begin
  -- 다른 사람이 추가했으면 "공유받은 일정", 없으면 "그 외"로 (REQ-SHARE-005)
  if new.category_id is null then
    select c.id into new.category_id
    from public.categories c
    where c.user_id = new.user_id and c.system_key in ('shared', 'etc')
    order by case c.system_key when 'shared' then 0 else 1 end
    limit 1;
  end if;

  if not exists (
    select 1 from public.categories c
    where c.id = new.category_id and c.user_id = new.user_id
  ) then
    raise exception 'category does not belong to the participant';
  end if;

  select e.time_type into v_time_type from public.events e where e.id = new.event_id;
  if (v_time_type = 'all_day' and new.reminder not in ('none', '9am'))
     or (v_time_type <> 'all_day' and new.reminder not in ('none', '30m', '1d')) then
    raise exception 'reminder % is not allowed for % events', new.reminder, v_time_type;
  end if;

  return new;
end;
$$;

create trigger participants_before_write
  before insert or update on public.event_participants
  for each row execute function public.participants_before_write();

-- 마지막 참여자가 빠지면 일정 삭제 (REQ-EVENT-008)
create function public.participants_after_delete()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (select 1 from public.event_participants ep where ep.event_id = old.event_id) then
    delete from public.events e where e.id = old.event_id;
  end if;
  return old;
end;
$$;

create trigger participants_after_delete
  after delete on public.event_participants
  for each row execute function public.participants_after_delete();

-- 다른 사람이 나를 추가하면 공유받음 알림 (REQ-NOTI-005, 008)
create function public.participants_after_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.added_by is not null and new.added_by <> new.user_id then
    insert into public.notifications (user_id, type, actor_id, event_id, event_title)
    select new.user_id, 'event_shared', new.added_by, e.id, e.title
    from public.events e where e.id = new.event_id;
  end if;
  return new;
end;
$$;

create trigger participants_after_insert
  after insert on public.event_participants
  for each row execute function public.participants_after_insert();

------------------------------------------------------------
-- 일정
------------------------------------------------------------
-- 수정 직전: 수정한 사람과 시각 기록 (NFR-010)
create function public.events_before_update()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  if auth.uid() is not null then
    new.updated_by := auth.uid();
  end if;
  return new;
end;
$$;

create trigger events_before_update
  before update on public.events
  for each row execute function public.events_before_update();

-- 수정 후: 시간 형태가 바뀌어 맞지 않게 된 미리 알림은 "없음"으로 되돌리고,
-- 수정한 사람을 뺀 참여자에게 수정 알림 (REQ-NOTI-006, 008)
create function public.events_after_update()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_changed text[] := '{}';
begin
  if (old.time_type = 'all_day') <> (new.time_type = 'all_day') then
    update public.event_participants ep set reminder = 'none'
    where ep.event_id = new.id and ep.reminder <> 'none';
  end if;

  if new.title is distinct from old.title then
    v_changed := array_append(v_changed, 'title');
  end if;
  if (new.time_type, new.start_date, new.end_date, new.start_at, new.end_at, new.time_zone)
     is distinct from
     (old.time_type, old.start_date, old.end_date, old.start_at, old.end_at, old.time_zone) then
    v_changed := array_append(v_changed, 'time');
  end if;
  if new.location is distinct from old.location then
    v_changed := array_append(v_changed, 'location');
  end if;
  if new.memo is distinct from old.memo then
    v_changed := array_append(v_changed, 'memo');
  end if;
  if (new.repeat_type, new.repeat_weekdays, new.repeat_until)
     is distinct from (old.repeat_type, old.repeat_weekdays, old.repeat_until) then
    v_changed := array_append(v_changed, 'repeat');
  end if;

  if cardinality(v_changed) > 0 then
    insert into public.notifications (user_id, type, actor_id, event_id, event_title, changed_fields)
    select ep.user_id, 'event_updated', new.updated_by, new.id, new.title, v_changed
    from public.event_participants ep
    where ep.event_id = new.id
      and ep.user_id is distinct from new.updated_by;
  end if;

  return new;
end;
$$;

create trigger events_after_update
  after update on public.events
  for each row execute function public.events_after_update();

-- 일정 만들기: 일정, 내 참여자 행, 공유할 사람의 참여자 행을 한 번에 (REQ-EVENT-001, REQ-SHARE-001~002)
create function public.create_event(
  p_title text,
  p_time_type text,
  p_category_id uuid,
  p_location text default null,
  p_memo text default null,
  p_start_date date default null,
  p_end_date date default null,
  p_start_at timestamptz default null,
  p_end_at timestamptz default null,
  p_time_zone text default 'Asia/Seoul',
  p_repeat_type text default 'none',
  p_repeat_weekdays smallint[] default null,
  p_repeat_until date default null,
  p_reminder text default 'none',
  p_share_with uuid[] default '{}'
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me uuid := auth.uid();
  v_event_id uuid;
  v_user uuid;
begin
  if v_me is null then
    raise exception 'not authenticated';
  end if;

  insert into public.events (
    title, location, memo, time_type, start_date, end_date, start_at, end_at,
    time_zone, repeat_type, repeat_weekdays, repeat_until, created_by, updated_by
  ) values (
    p_title, p_location, p_memo, p_time_type, p_start_date, p_end_date, p_start_at, p_end_at,
    p_time_zone, p_repeat_type, p_repeat_weekdays, p_repeat_until, v_me, v_me
  ) returning id into v_event_id;

  insert into public.event_participants (event_id, user_id, category_id, reminder, added_by)
  values (v_event_id, v_me, p_category_id, p_reminder, v_me);

  foreach v_user in array coalesce(p_share_with, '{}') loop
    continue when v_user = v_me;
    if not public.is_connected_with(v_user) then
      raise exception 'can only share with connected users';
    end if;
    insert into public.event_participants (event_id, user_id, added_by)
    values (v_event_id, v_user, v_me)
    on conflict do nothing;
  end loop;

  return v_event_id;
end;
$$;

-- 참여자 추가 (REQ-SHARE-003). 반환: 새로 추가된 인원 수
create function public.add_participants(p_event_id uuid, p_user_ids uuid[])
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me uuid := auth.uid();
  v_user uuid;
  v_added integer := 0;
  v_rows integer;
begin
  if not public.is_event_participant(p_event_id) then
    raise exception 'not a participant of this event';
  end if;

  foreach v_user in array coalesce(p_user_ids, '{}') loop
    if not public.is_connected_with(v_user) then
      raise exception 'can only add connected users';
    end if;
    insert into public.event_participants (event_id, user_id, added_by)
    values (p_event_id, v_user, v_me)
    on conflict do nothing;
    get diagnostics v_rows = row_count;
    v_added := v_added + v_rows;
  end loop;

  return v_added;
end;
$$;

-- 참여자 목록: 이름과 고유 아이디만 (REQ-EVENT-009, NFR-006)
create function public.get_event_participants(p_event_id uuid)
returns table (user_id uuid, handle text, name text, joined_at timestamptz)
language sql
stable
security definer
set search_path = ''
as $$
  select m.id, m.handle, m.name, ep.joined_at
  from public.event_participants ep
  join public.members m on m.id = ep.user_id
  where ep.event_id = p_event_id
    and public.is_event_participant(p_event_id)
  order by ep.joined_at;
$$;

-- 일정 검색: 내가 참여 중인 일정의 제목, 장소, 메모 (REQ-SEARCH-001~002)
-- 날짜순 정렬과 반복 일정 묶기는 앱에서 한다 (REQ-SEARCH-003)
create function public.search_events(p_keyword text)
returns table (
  id uuid, title text, location text, memo text, time_type text,
  start_date date, end_date date, start_at timestamptz, end_at timestamptz, time_zone text,
  repeat_type text, repeat_weekdays smallint[], repeat_until date, category_id uuid
)
language sql
stable
security definer
set search_path = ''
as $$
  select e.id, e.title, e.location, e.memo, e.time_type,
         e.start_date, e.end_date, e.start_at, e.end_at, e.time_zone,
         e.repeat_type, e.repeat_weekdays, e.repeat_until, ep.category_id
  from public.events e
  join public.event_participants ep on ep.event_id = e.id and ep.user_id = auth.uid()
  where char_length(btrim(p_keyword)) > 0
    and (strpos(lower(e.title), lower(btrim(p_keyword))) > 0
      or strpos(lower(coalesce(e.location, '')), lower(btrim(p_keyword))) > 0
      or strpos(lower(coalesce(e.memo, '')), lower(btrim(p_keyword))) > 0);
$$;

------------------------------------------------------------
-- 연결 알림 (REQ-NOTI-007)
------------------------------------------------------------
create function public.connections_after_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.notifications (user_id, type, actor_id)
  values (new.addressee_id, 'connection_requested', new.requester_id);
  return new;
end;
$$;

create trigger connections_after_insert
  after insert on public.connections
  for each row execute function public.connections_after_insert();

create function public.connections_after_update()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.status = 'pending' and new.status = 'accepted' then
    insert into public.notifications (user_id, type, actor_id)
    values (new.requester_id, 'connection_accepted', new.addressee_id);
  end if;
  return new;
end;
$$;

create trigger connections_after_update
  after update on public.connections
  for each row execute function public.connections_after_update();

------------------------------------------------------------
-- 푸시 기기 토큰 등록: 같은 토큰이 있으면 주인을 바꾼다 (REQ-AUTH-006)
------------------------------------------------------------
create function public.register_device_token(p_token text, p_platform text default 'android')
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;
  insert into public.device_tokens (user_id, token, platform)
  values (auth.uid(), p_token, p_platform)
  on conflict (token) do update
    set user_id = excluded.user_id, platform = excluded.platform, updated_at = now();
end;
$$;

------------------------------------------------------------
-- 함수 실행 권한: 기본으로 열려 있는 실행 권한을 닫고 필요한 것만 연다
------------------------------------------------------------
revoke execute on all functions in schema public from public, anon, authenticated;

grant execute on function public.is_handle_available(text) to anon, authenticated;
grant execute on function public.find_user_by_handle(text) to authenticated;
grant execute on function public.send_connection_request(uuid) to authenticated;
grant execute on function public.create_event(
  text, text, uuid, text, text, date, date, timestamptz, timestamptz,
  text, text, smallint[], date, text, uuid[]
) to authenticated;
grant execute on function public.add_participants(uuid, uuid[]) to authenticated;
grant execute on function public.get_event_participants(uuid) to authenticated;
grant execute on function public.search_events(text) to authenticated;
grant execute on function public.register_device_token(text, text) to authenticated;

-- RLS 정책에서 쓰는 도우미
grant execute on function public.is_connected_with(uuid) to authenticated;
grant execute on function public.can_see_member(uuid) to authenticated;
grant execute on function public.is_event_participant(uuid) to authenticated;
