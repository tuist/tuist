defmodule Tuist.OnceEvents.TestReportPublication do
  @moduledoc """
  Durable, immutable snapshot of every shared-store row in a Once test report.
  Progress is durable per chunk. Uncertain writes require reconciliation, never
  blind replay based on a finite ClickHouse deduplication window.
  """
  use Ecto.Schema

  @primary_key {:id, Ecto.UUID, autogenerate: false}
  schema "once_test_report_publications" do
    field :payload, :binary
    field :state, :string, default: "preparing"
    field :owner, :string
    field :first_attempt_at, :utc_datetime
    field :next_chunk, :integer, default: 0
    field :in_flight_chunk, :integer
    field :effects_dispatched_at, :utc_datetime
    timestamps(type: :utc_datetime)
  end
end
