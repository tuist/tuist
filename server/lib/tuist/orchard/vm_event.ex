defmodule Tuist.Orchard.VMEvent do
  @moduledoc """
  Append-only stream of events for a single VM. Workers POST batches
  of events (logs, condition transitions); clients tail them via
  `GET /v1/vms/:name/events?since=N` for `kubectl logs` and the
  Orchard CLI's `orchard logs` command.

  `sequence` is monotonic per-VM; Postgres assigns it via a
  per-(vm_name) counter so clients can resume after a network blip
  without missing events.
  """
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "orchard_vm_events" do
    field :vm_name, :string
    field :sequence, :integer
    field :kind, :string
    field :payload, :map, default: %{}
    field :inserted_at, :utc_datetime_usec
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, [:vm_name, :sequence, :kind, :payload, :inserted_at])
    |> validate_required([:vm_name, :sequence, :kind])
    |> validate_inclusion(:kind, ~w(log condition status))
  end
end
