defmodule Tuist.OnceEvents.SystemSample do
  @moduledoc """
  One host-resource sample projected from a `once.events.v1`
  SystemSampled event. Feeds the Timeline tab's CPU / Memory /
  Network charts.
  """
  use Ecto.Schema

  @primary_key {:id, UUIDv7, autogenerate: true}
  schema "once_system_samples" do
    field :once_run_id, UUIDv7
    field :run_id, :string
    field :project_id, :integer

    field :at_ms, :integer
    field :cpu_percent, :float, default: 0.0
    field :memory_bytes, :integer, default: 0
    field :network_in_bytes, :integer, default: 0
    field :network_out_bytes, :integer, default: 0

    field :observed_at, :utc_datetime_usec
  end
end
