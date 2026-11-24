defmodule Tuist.TestImpactAnalysis.Snapshot do
  @moduledoc """
  A test map of coverage-based test selection, valid at one commit for one
  scope (repository, scheme, platform): its tests, with what each executed,
  are in ClickHouse under its id (`Tuist.TestImpactAnalysis.Snapshots`).

  A `checkpoint` holds every test of a full run. An `overlay` holds what a
  later run changed against the checkpoint at its impact run's baseline
  (`checkpoint_id`, `base_sha`), keyed by the commit that impact run
  checked out. A checkpoint of a selective run whose skips were all
  carried also holds copies of the targets selective testing skipped by hash
  (`carried_targets`, `name <> "\\u001F" <> hash`), measured as early as
  `evidence_measured_at`; a skipped target without tests is listed there
  without a row. This is a PostgreSQL entity.
  """
  use Ecto.Schema

  @primary_key {:id, Ecto.UUID, autogenerate: false}
  schema "test_impact_snapshots" do
    field :project_id, :integer
    field :repository_id, :integer
    field :commit_sha, :string
    field :kind, Ecto.Enum, values: [:checkpoint, :overlay]
    field :checkpoint_id, Ecto.UUID
    field :base_sha, :string
    field :scheme, :string, default: ""
    field :platform, :string, default: ""
    field :git_branch, :string, default: ""
    field :test_run_ids, {:array, Ecto.UUID}, default: []
    field :test_impact_run_id, Ecto.UUID
    field :tests_count, :integer, default: 0
    field :overridden_count, :integer, default: 0
    field :carried_targets, {:array, :string}, default: []
    field :ran_at, :utc_datetime_usec
    field :evidence_measured_at, :utc_datetime_usec
    field :expires_at, :utc_datetime_usec

    timestamps(type: :utc_datetime, updated_at: false)
  end
end
