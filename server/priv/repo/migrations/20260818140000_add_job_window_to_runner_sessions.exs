defmodule Tuist.Repo.Migrations.AddJobWindowToRunnerSessions do
  @moduledoc """
  Persists GitHub's own workflow_job execution window on the billing
  session, so invoicing charges for the time we were running the
  customer's work rather than for how long their Pod occupied a host.

  The Pod outlives the job on both ends: it boots a macOS VM before the
  job can start and holds the host through post-job cache work and
  teardown afterwards. That overhead is ours to optimize, not the
  customer's to pay for, so the session's own `started_at` / `ended_at`
  stay the operational record (capacity signals, orphan detection) while
  these two columns become the billable window.

  Both are nullable, and billing charges nothing when either is absent:
  a job cancelled while queued never ran, and a lost completion webhook
  is not proof that it did. That keeps the module's existing bias toward
  undercharging rather than inventing a window we cannot evidence.
  """
  use Ecto.Migration

  def change do
    alter table(:runner_sessions) do
      add :job_started_at, :timestamptz
      add :job_ended_at, :timestamptz
    end
  end
end
