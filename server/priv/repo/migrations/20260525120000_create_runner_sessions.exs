defmodule Tuist.Repo.Migrations.CreateRunnerSessions do
  use Ecto.Migration

  # Billing-grade record of every runner Pod we provisioned for
  # this account. Distinct from `runner_claims` (in-flight
  # coordination, deleted on completion) and `runner_jobs`
  # (ClickHouse, workflow_job lifecycle as reported by GitHub) —
  # this table is append-only and exists specifically to anchor
  # billing.
  #
  # ## Why a third table
  #
  # `runner_claims` is deleted on completion, so it can't drive
  # historical invoicing. `runner_jobs` measures the
  # workflow_job's runtime from GitHub's perspective
  # (`started_at`/`completed_at` as reported by the runner agent
  # back to GitHub) which is sensitive to clock skew, dropped
  # completion webhooks, and retries via `Jobs.record_queued/1`.
  # For metered compute we want the *sandbox*'s wall-clock
  # lifetime — the runner Pod we provisioned and the customer
  # held — which is the same signal Namespace and Blacksmith bill
  # against.
  #
  # ## Source of truth
  #
  # The cleanest signal is the `runners-controller` (Go process)
  # observing Pod `creationTimestamp` and `deletionTimestamp` and
  # POSTing them back to us. That's the eventual goal. Until
  # then we approximate with the timestamps the Tuist server
  # already owns:
  #
  #   * `started_at` ← `runner_claims.claimed_at` (a few hundred
  #     ms before the controller creates the Pod)
  #   * `ended_at` ← `runner_jobs.completed_at` from the GitHub
  #     completion webhook (a few seconds before the controller
  #     tears the Pod down)
  #
  # That's already meaningfully better than billing from the
  # workflow_job-level `started_at`/`completed_at` because both
  # ends correspond to events *we* observed server-side and can
  # stand behind in a dispute. When the controller starts
  # emitting Pod timestamps directly, the Billing module
  # switches over with no schema change — the new columns
  # already exist.
  #
  # ## Retries
  #
  # `Jobs.record_queued/1` lets the same `workflow_job_id` be
  # re-queued after a release / stale recovery. Each re-claim
  # creates a brand new session row (no unique constraint on
  # `workflow_job_id` — the surrogate `id` is the PK), so the
  # customer is billed for every Pod they actually held.
  def change do
    create table(:runner_sessions) do
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :workflow_job_id, :bigint, null: false
      add :fleet_name, :string, null: false
      add :pod_name, :string, null: false, default: ""
      add :runner_name, :string, null: false, default: ""
      # Denormalised from the corresponding workflow_job so the
      # Jobs page's repo / workflow_name page-level filters can
      # narrow the Compute Minutes widget without joining
      # against ClickHouse.
      add :repo, :string, null: false, default: ""
      add :workflow_name, :string, null: false, default: ""

      # The window we'll bill the customer for. `started_at` is
      # set on session creation (claim-win) and never changes.
      # `ended_at` stays NULL until completion; the Billing
      # module clamps open sessions to `now()` (or the billing
      # window's end) so an orphaned Pod doesn't bill forever.
      add :started_at, :timestamptz, null: false
      add :ended_at, :timestamptz

      timestamps(type: :timestamptz)
    end

    # Primary billing-period scan: "all sessions for account X
    # that overlap [start, end]". Indexed on (account_id,
    # started_at) for partition pruning; the open-vs-closed
    # filter is cheap in the planner.
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:runner_sessions, [:account_id, :started_at])

    # `Jobs.complete/2` closes a session by workflow_job_id; we
    # want that lookup to hit an index. NOT unique because of
    # the retry path described above.
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:runner_sessions, [:workflow_job_id])
  end
end
