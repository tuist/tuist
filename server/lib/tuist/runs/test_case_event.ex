defmodule Tuist.Runs.TestCaseEvent do
  @moduledoc """
  Represents an audit event for a test case.

  Events track state changes like:
  - first_run (first time test was seen on default branch)
  - marked_flaky / unmarked_flaky
  - quarantined / unquarantined

  Each event records who performed the action (user or system).

  This is a ClickHouse entity using ReplacingMergeTree. For first_run events,
  a deterministic ID based on test_case_id ensures deduplication.
  """
  use Ecto.Schema

  import Ecto.Changeset

  @derive {
    Flop.Schema,
    filterable: [:test_case_id, :event_type],
    sortable: [:inserted_at, :id],
    default_order: %{
      order_by: [:inserted_at, :id],
      order_directions: [:desc, :desc]
    },
    default_limit: 20,
    max_limit: 100
  }

  @primary_key {:id, Ecto.UUID, autogenerate: false}
  schema "test_case_events" do
    field :test_case_id, Ecto.UUID
    field :event_type, Ch, type: "LowCardinality(String)"
    field :actor_id, Ch, type: "Nullable(Int64)"
    field :inserted_at, Ch, type: "DateTime64(6)"

    belongs_to :actor, Tuist.Accounts.Account, foreign_key: :actor_id, define_field: false
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, [:id, :test_case_id, :event_type, :actor_id, :inserted_at])
    |> validate_required([:id, :test_case_id, :event_type])
  end

  @doc """
  Generates a deterministic UUID for first_run events based on test_case_id.
  This ensures ReplacingMergeTree deduplicates duplicate first_run events.
  """
  def first_run_id(test_case_id) do
    <<a::32, b::16, c::16, d::16, e::48>> =
      :md5
      |> :crypto.hash("first_run:#{test_case_id}")
      |> binary_part(0, 16)

    Ecto.UUID.cast!(<<a::32, b::16, 4::4, c::12, 2::2, d::14, e::48>>)
  end
end
