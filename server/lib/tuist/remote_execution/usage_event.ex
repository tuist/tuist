defmodule Tuist.RemoteExecution.UsageEvent do
  @moduledoc """
  One remote execution VM's action, as the node measured it: how long the
  executor ran in the single-use VM, from its start to its exit, which
  includes fetching inputs and uploading outputs but not queueing, booting
  or preparing the VM. Recorded for both scheduled and leased executions.
  """
  use Ecto.Schema
  use Tuist.Ingestion.Bufferable

  @primary_key false
  schema "remote_execution_usage_events" do
    field :id, Ch, type: "UUID"
    field :account_id, Ch, type: "Int64"
    field :project_id, Ch, type: "Int64"
    field :sandbox_id, Ch, type: "UUID"
    field :mode, Ch, type: "LowCardinality(String)"
    field :vcpus, Ch, type: "UInt16"
    field :memory_mb, Ch, type: "UInt32"
    field :duration_ms, Ch, type: "UInt32"
    field :inserted_at, Ch, type: "DateTime64(6)"
  end
end
