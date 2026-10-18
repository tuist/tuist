defmodule Tuist.Shards.Workflow do
  @moduledoc """
  Authoritative plan and merged-run snapshot. Its presence, not a feature flag
  evaluated by a reader, selects PostgreSQL coordination for the plan.
  """
  use Ecto.Schema

  @primary_key {:id, Ecto.UUID, autogenerate: false}
  schema "shard_workflows" do
    field :project_id, :integer
    field :reference, :string
    field :shard_count, :integer
    field :granularity, :string
    field :build_run_id, Ecto.UUID
    field :gradle_build_id, Ecto.UUID
    field :test_run_id, Ecto.UUID
    field :snapshot, :map
    field :version, :integer, default: 0
    field :projected_version, :integer, default: -1
    field :projection_repair_at, :utc_datetime_usec
    has_many :shards, Tuist.Shards.WorkflowShard
    # Preserve database-clock precision for latest-reference ordering and idle deadlines.
    # credo:disable-for-next-line Credo.Checks.TimestampsType
    timestamps(type: :utc_datetime_usec)
  end
end
