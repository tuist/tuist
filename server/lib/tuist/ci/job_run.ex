defmodule Tuist.CI.JobRun do
  @moduledoc """
  A job run represents execution of a CI job within a workflow.
  This is a ClickHouse entity that stores CI job run data.
  """
  use Ecto.Schema

  import Ecto.Changeset

  @derive {
    Flop.Schema,
    filterable: [
      :project_id,
      :workflow_id,
      :workflow_name,
      :job_id,
      :job_name,
      :git_branch,
      :git_commit_sha,
      :runner_machine,
      :runner_configuration,
      :status
    ],
    sortable: [:started_at, :duration_ms, :workflow_name, :job_name]
  }

  @primary_key {:id, Ecto.UUID, autogenerate: false}
  schema "ci_job_runs" do
    field :project_id, Ch, type: "Int64"

    field :workflow_id, :string
    field :workflow_name, :string
    field :job_id, :string
    field :job_name, :string

    field :git_branch, :string
    field :git_commit_sha, :string
    field :git_ref, :string

    field :runner_machine, :string
    field :runner_configuration, :string

    field :status, Ch, type: "Enum8('pending' = 0, 'running' = 1, 'success' = 2, 'failure' = 3, 'cancelled' = 4)"
    field :duration_ms, Ch, type: "Nullable(Int32)"
    field :started_at, Ch, type: "DateTime64(6)"
    field :inserted_at, Ch, type: "DateTime64(6)"
  end

  def create_changeset(job_run, attrs) do
    job_run
    |> cast(attrs, [
      :id,
      :project_id,
      :workflow_id,
      :workflow_name,
      :job_id,
      :job_name,
      :git_branch,
      :git_commit_sha,
      :git_ref,
      :runner_machine,
      :runner_configuration,
      :status,
      :duration_ms,
      :started_at,
      :inserted_at
    ])
    |> validate_required([
      :id,
      :project_id,
      :workflow_id,
      :workflow_name,
      :job_id,
      :job_name,
      :git_branch,
      :git_commit_sha,
      :runner_machine,
      :status,
      :started_at
    ])
  end
end
