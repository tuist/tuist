defmodule Tuist.Runners.JobStep do
  @moduledoc """
  One step of a workflow_job. Stored in ClickHouse (`runner_job_steps`)
  as a ReplacingMergeTree row per `(workflow_job_id, number)` so
  webhook retries collapse on merge. See `Tuist.Runners.JobSteps` for
  the read/write contract and `Tuist.IngestRepo.Migrations.CreateRunnerJobSteps`
  for the schema rationale.
  """
  use Ecto.Schema

  @primary_key false

  schema "runner_job_steps" do
    field :workflow_job_id, Ch, type: "Int64"
    field :account_id, Ch, type: "Int64"
    field :number, Ch, type: "UInt16"
    field :name, Ch, type: "String", default: ""
    field :status, Ch, type: "LowCardinality(String)", default: ""
    field :conclusion, Ch, type: "LowCardinality(String)", default: ""
    field :started_at, Ch, type: "Nullable(DateTime64(6, 'UTC'))", default: nil
    field :completed_at, Ch, type: "Nullable(DateTime64(6, 'UTC'))", default: nil
    field :inserted_at, Ch, type: "DateTime64(6, 'UTC')"
  end
end
