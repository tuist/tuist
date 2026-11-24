defmodule Tuist.Sandboxes.UsageEvent do
  @moduledoc """
  A running Linux agent sandbox's CPU between two node reports: the wall
  time between them, the CPU its VM used, its guarantee, and what it is
  billed, the larger of its CPU floor (`Tuist.Sandboxes.Pricing.cpu_floor_milli/1`)
  over that time and the CPU used. Memory is billed max(request, use): the
  request comes from the sandbox's sessions, and `excess_memory_mib_ms` is
  what the VM held (`used_memory_bytes`, its process's Pss at the report)
  past its request and VMM overhead, times the interval.
  """
  use Ecto.Schema
  use Tuist.Ingestion.Bufferable

  @primary_key false
  schema "sandbox_usage_events" do
    field :id, Ch, type: "UUID"
    field :account_id, Ch, type: "Int64"
    field :sandbox_id, Ch, type: "UUID"
    field :source, Ch, type: "LowCardinality(String)"
    field :vcpus, Ch, type: "UInt16"
    field :memory_mb, Ch, type: "UInt32"
    field :guaranteed_cpu_milli, Ch, type: "UInt32"
    field :duration_ms, Ch, type: "UInt32"
    field :used_cpu_ms, Ch, type: "UInt64"
    field :billed_cpu_ms, Ch, type: "UInt64"
    field :used_memory_bytes, Ch, type: "UInt64"
    field :excess_memory_mib_ms, Ch, type: "UInt64"
    field :inserted_at, Ch, type: "DateTime64(6)"
  end
end
