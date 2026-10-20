-- ============================================================
-- Weld Path — Leaderboard fix (run ONCE in Supabase SQL Editor)
-- What this does:
--   1) The leaderboard now includes EVERYONE (students + teacher/admin).
--   2) Points = final-exam points (as before)
--      + stage points: 1 point for every correct answer in MCQ stages.
--      A stage counts only ONCE, at its BEST result — replaying the
--      same stage again and again does not add more points.
-- Nothing else changes. Safe to run once.
-- ============================================================

drop function if exists public.leaderboard_top(int);

create or replace function public.leaderboard_top(p_limit int default 20)
returns table(rnk bigint, full_name text, points bigint, is_me boolean)
language sql
security definer
set search_path = public
as $$
  with pts as (
    select
      p.id,
      p.full_name,
      coalesce((select sum(er.points_awarded)
                from public.exam_runs er
                where er.user_id = p.id), 0)
      + coalesce((select sum(b.best)
                  from (select max(msa.correct) as best
                        from public.mcq_stage_attempts msa
                        where msa.user_id = p.id
                        group by msa.level_id, msa.stage_no) b), 0)
      as total
    from public.profiles p
  )
  select rank() over (order by pts.total desc) as rnk,
         pts.full_name,
         pts.total as points,
         (pts.id = auth.uid()) as is_me
  from pts
  order by pts.total desc, pts.full_name asc
  limit p_limit;
$$;

grant execute on function public.leaderboard_top(int) to authenticated;
