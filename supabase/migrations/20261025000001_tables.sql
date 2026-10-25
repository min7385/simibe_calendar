-- 심이베 캘린더 1/4: 테이블, 제약조건, 인덱스
-- 기준 문서: docs/03-design/ERD및테이블정의서.md

-- 회원 (3.1)
create table public.members (
  id uuid primary key references auth.users (id) on delete cascade,
  handle text not null unique
    check (handle ~ '^[a-z0-9]{8,20}$' and handle ~ '[a-z]' and handle ~ '[0-9]'),
  name text not null check (char_length(btrim(name)) between 1 and 20),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- 연결 (3.2)
create table public.connections (
  id uuid primary key default gen_random_uuid(),
  requester_id uuid not null references public.members (id) on delete cascade,
  addressee_id uuid not null references public.members (id) on delete cascade,
  status text not null default 'pending' check (status in ('pending', 'accepted')),
  created_at timestamptz not null default now(),
  accepted_at timestamptz,
  check (requester_id <> addressee_id)
);

create unique index connections_pair_uidx
  on public.connections (least(requester_id, addressee_id), greatest(requester_id, addressee_id));
create index connections_requester_idx on public.connections (requester_id);
create index connections_addressee_idx on public.connections (addressee_id);

-- 일정 (3.3)
create table public.events (
  id uuid primary key default gen_random_uuid(),
  title text not null check (char_length(btrim(title)) between 1 and 100),
  location text check (char_length(location) <= 100),
  memo text check (char_length(memo) <= 1000),
  time_type text not null check (time_type in ('all_day', 'start', 'end', 'range')),
  start_date date,
  end_date date,
  start_at timestamptz,
  end_at timestamptz,
  time_zone text not null default 'Asia/Seoul',
  repeat_type text not null default 'none' check (repeat_type in ('none', 'weekly', 'monthly', 'yearly')),
  repeat_weekdays smallint[],
  repeat_until date,
  created_by uuid references public.members (id) on delete set null,
  updated_by uuid references public.members (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint events_time_check check (
    case time_type
      when 'all_day' then start_date is not null and end_date is not null and end_date >= start_date
                          and start_at is null and end_at is null
      when 'start'   then start_at is not null and end_at is null
                          and start_date is null and end_date is null
      when 'end'     then end_at is not null and start_at is null
                          and start_date is null and end_date is null
      when 'range'   then start_at is not null and end_at is not null and end_at > start_at
                          and start_date is null and end_date is null
    end
  ),

  constraint events_repeat_check check (
    case repeat_type
      when 'none'   then repeat_weekdays is null and repeat_until is null
      when 'weekly' then repeat_weekdays is not null
                         and cardinality(repeat_weekdays) between 1 and 7
                         and repeat_weekdays <@ array[0, 1, 2, 3, 4, 5, 6]::smallint[]
                         and repeat_until is not null
      else               repeat_weekdays is null and repeat_until is not null
    end
  ),

  -- 반복 종료 날짜는 일정의 시작 날짜(일정 시간대 기준) 이후여야 한다
  constraint events_repeat_until_check check (
    repeat_until is null or repeat_until >= (
      case time_type
        when 'all_day' then start_date
        when 'end'     then (end_at at time zone time_zone)::date
        else                (start_at at time zone time_zone)::date
      end
    )
  )
);

create index events_start_at_idx on public.events (start_at);
create index events_end_at_idx on public.events (end_at);
create index events_start_date_idx on public.events (start_date);
create index events_end_date_idx on public.events (end_date);
create index events_repeat_until_idx on public.events (repeat_until);

-- 분류 (3.5)
create table public.categories (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.members (id) on delete cascade,
  name text not null check (char_length(btrim(name)) between 1 and 10),
  color text not null check (color in (
    '#E53935', '#E91E63', '#8E24AA', '#7E57C2', '#3949AB', '#42A5F5',
    '#00ACC1', '#43A047', '#9CCC65', '#FDD835', '#EF6C00', '#9E9E9E'
  )),
  sort_order integer not null,
  system_key text check (system_key in ('shared', 'etc')),
  created_at timestamptz not null default now(),
  unique (user_id, name),
  unique (user_id, system_key)
);

-- 일정 참여자 (3.4)
create table public.event_participants (
  event_id uuid not null references public.events (id) on delete cascade,
  user_id uuid not null references public.members (id) on delete cascade,
  category_id uuid not null references public.categories (id),
  reminder text not null default 'none' check (reminder in ('none', '30m', '1d', '9am')),
  added_by uuid references public.members (id) on delete set null,
  joined_at timestamptz not null default now(),
  primary key (event_id, user_id)
);

create index event_participants_user_idx on public.event_participants (user_id);
create index event_participants_category_idx on public.event_participants (category_id);

-- 알림 목록 (3.6)
create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.members (id) on delete cascade,
  type text not null check (type in (
    'event_shared', 'event_updated', 'connection_requested', 'connection_accepted'
  )),
  actor_id uuid references public.members (id) on delete set null,
  event_id uuid references public.events (id) on delete set null,
  event_title text,
  changed_fields text[],
  is_read boolean not null default false,
  created_at timestamptz not null default now()
);

create index notifications_user_created_idx on public.notifications (user_id, created_at desc);
create index notifications_user_unread_idx on public.notifications (user_id) where is_read = false;

-- 푸시 기기 토큰 (3.7)
create table public.device_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.members (id) on delete cascade,
  token text not null unique,
  platform text not null default 'android' check (platform in ('android', 'ios')),
  updated_at timestamptz not null default now()
);

create index device_tokens_user_idx on public.device_tokens (user_id);
