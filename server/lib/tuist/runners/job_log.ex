defmodule Tuist.Runners.JobLog do
  @moduledoc """
  A single captured line of a runner job's stdout, stored in
  ClickHouse (`runner_job_logs`) as a ReplacingMergeTree keyed on
  `(workflow_job_id, line_number)`. See `Tuist.Runners.JobLogs` for
  the ingest + read contract and the rationale for storing logs in
  ClickHouse rather than object storage.
  """
  use Ecto.Schema

  @primary_key false

  schema "runner_job_logs" do
    field :workflow_job_id, Ch, type: "Int64"
    field :account_id, Ch, type: "Int64"
    field :line_number, Ch, type: "UInt32"
    field :ts, Ch, type: "DateTime64(6, 'UTC')"
    field :message, Ch, type: "String"
    field :inserted_at, Ch, type: "DateTime64(6, 'UTC')"
  end
end
