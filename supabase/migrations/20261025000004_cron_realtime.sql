-- 심이베 캘린더 4/4: 예약 작업과 실시간 반영
-- 기준 문서: docs/03-design/ERD및테이블정의서.md 5.2, 6.1

-- 90일이 지난 알림 삭제 (REQ-NOTI-012). 매일 03:00 (한국 시간) = 18:00 UTC
create extension if not exists pg_cron with schema pg_catalog;

select cron.schedule(
  'delete-old-notifications',
  '0 18 * * *',
  $$delete from public.notifications where created_at < now() - interval '90 days'$$
);

-- 실시간 반영 대상 테이블 (REQ-SHARE-006, NFR-009). Realtime도 RLS를 따른다
alter publication supabase_realtime add table
  public.events,
  public.event_participants,
  public.notifications,
  public.connections;
