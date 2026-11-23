defmodule Tuist.Sandboxes.SandboxEvent do
  @moduledoc """
  A sandbox lifecycle change stored in ClickHouse.
  """
  use Ecto.Schema
  use Tuist.Ingestion.Bufferable

  @primary_key false
  schema "sandbox_events" do
    field :id, Ch, type: "UUID"
    field :account_id, Ch, type: "Int64"
    field :sandbox_id, Ch, type: "UUID"
    field :event, Ch, type: "LowCardinality(String)"
    field :source, Ch, type: "LowCardinality(String)"
    field :vcpus, Ch, type: "UInt16"
    field :memory_mb, Ch, type: "UInt32"
    field :workspace_gb, Ch, type: "UInt16"
    field :boot_source, Ch, type: "LowCardinality(String)"
    field :duration_ms, Ch, type: "UInt32"
    field :guaranteed_cpu_milli, Ch, type: "UInt32"
    field :error_message, Ch, type: "String"
    field :node_name, Ch, type: "LowCardinality(String)"
    field :template, Ch, type: "LowCardinality(String)"
    field :inserted_at, Ch, type: "DateTime64(6)"
  end
end
