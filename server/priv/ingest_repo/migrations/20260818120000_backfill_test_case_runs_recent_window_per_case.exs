defmodule Tuist.IngestRepo.Migrations.BackfillTestCaseRunsRecentWindowPerCase do
  @moduledoc """
  Inert. This version seeded `test_case_runs_recent_window_per_case` from
  `test_case_runs_recent_100_per_case`; the seeding was removed and the version
  kept so environments that already recorded it stay consistent.

  It ran as a helm `pre-upgrade` hook, so nothing shipped while it failed, and it
  failed four production deploys on 2026-08-18. Two array-size bugs were found
  and fixed along the way (#12453, #12457). What could not be fixed by a constant
  was memory: the same range passes or fails depending on what else the ClickHouse
  replica is doing, so one project succeeded once and failed three times on
  identical data within six minutes, and a larger one failed on every retry.

  Removing it costs little. The packed table serves `window_type: "rolling"`
  alerts only — 2 alerts in 1 project, against 4072 `last_days` alerts across
  4070 projects that read `test_case_run_daily_stats_per_case` instead. An
  unseeded window degrades closed rather than wrong: a rolling window is
  evaluated only once the aggregate holds that many distinct runs, so those
  alerts stay dormant while the materialized view fills forward past their 75-run
  window, rather than reporting off partial history.

  If the historical window is wanted later, the removed implementation and the
  reasoning behind it are in this file's history, and a fresh migration is the
  place for it — that one should retry *and* subdivide, since identical retries
  clear a marginal overrun but never a large one.
  """
  use Ecto.Migration

  def up, do: :ok

  def down, do: :ok
end
