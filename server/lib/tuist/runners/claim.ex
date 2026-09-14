defmodule Tuist.Runners.Claim do
  @moduledoc """
  Thin Postgres claim-lock for the dispatch path. See
  `Tuist.Runners.Claims` for the operational API and the
  `runner_claims` migrations for the schema rationale.

  The primary key is `pod_name`, not the implicit `id`. A claim is one
  of the account's concurrency slots and a slot is held by a Pod, so the
  Pod is the identity; `workflow_job_id` is the job that Pod is
  currently reserved for and may be cleared when GitHub runs a
  different job on it. A partial unique index on `workflow_job_id`
  keeps at most one live claim per job, so the untargeted
  `INSERT … ON CONFLICT DO NOTHING` is still the atomic-claim
  primitive for both the Pod and the job.
  """
  use Ecto.Schema

  alias Tuist.Accounts.Account

  @primary_key {:pod_name, :string, []}

  schema "runner_claims" do
    # The workflow_job this Pod's slot is currently reserved for. NULL
    # once GitHub proves the Pod is running a different job: the job
    # goes back to the queue while the Pod keeps its slot for the job
    # it actually took.
    field :workflow_job_id, :integer
    field :fleet_name, :string
    field :claimed_at, :utc_datetime_usec
    field :platform, Ecto.Enum, values: [:linux, :macos]
    field :vcpus, :integer
    field :memory_gb, :integer
    # `claimed` (post-INSERT, pre-mint) or `running` (mint OK).
    # The stale reaper only targets `claimed`; a long-lived
    # `running` row is the active cap slot for a healthy build
    # and must not be reaped at the 5-min threshold.
    field :lifecycle_state, :string, default: "claimed"
    field :runner_name, :string, default: ""
    # The workflow_job GitHub actually ran on this runner, learned
    # from the `in_progress` / `completed` webhook's `runner_name`.
    # NULL until GitHub proves the runner ran something; may differ
    # from `workflow_job_id` (the claim-time guess) or stay NULL for
    # a runner GitHub never assigned work to.
    field :executed_workflow_job_id, :integer
    # First tick the reconciler saw this claim's Pod missing from a
    # complete cluster read. NULL means last observed present. Release
    # requires the absence to persist, so one bad read cannot free a
    # live runner's slot.
    field :pod_missing_since, :utc_datetime_usec

    belongs_to :account, Account
  end
end
