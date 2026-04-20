defmodule Tuist.Runners.OrchardWorker do
  @moduledoc """
  A single Scaleway bare-metal Mac that hosts an Orchard worker daemon.

  Workers always belong to an `OrchardWorkerPool`. Spec fields (name, Scaleway
  config) describe desired state and are copied from the pool at creation.
  Status fields (everything else) are owned by the reconciler/provisioner.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.Runners.OrchardWorkerPool

  @primary_key {:id, UUIDv7, autogenerate: true}
  @foreign_key_type UUIDv7

  @statuses [:queued, :provisioning, :online, :draining, :terminating, :terminated, :failed]

  @spec_fields [:name, :scaleway_zone, :scaleway_server_type, :scaleway_os]
  @status_fields [
    :status,
    :scaleway_server_id,
    :ip_address,
    :error_message,
    :last_seen_at,
    :provisioned_at,
    :terminated_at
  ]

  @name_regex ~r/^[a-z0-9][a-z0-9-]{0,62}[a-z0-9]$/

  schema "orchard_workers" do
    field :name, :string
    field :status, Ecto.Enum, values: @statuses, default: :queued
    field :scaleway_server_id, :string
    field :scaleway_zone, :string
    field :scaleway_server_type, :string
    field :scaleway_os, :string
    field :ip_address, :string
    field :error_message, :string
    field :last_seen_at, :utc_datetime
    field :provisioned_at, :utc_datetime
    field :terminated_at, :utc_datetime

    belongs_to :pool, OrchardWorkerPool

    timestamps(type: :utc_datetime)
  end

  def statuses, do: @statuses
  def active_statuses, do: [:queued, :provisioning, :online]

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:pool_id | @spec_fields])
    |> validate_required([:pool_id | @spec_fields])
    |> validate_format(:name, @name_regex, message: "must be lowercase alphanumeric with hyphens, 2-64 chars")
    |> unique_constraint(:name)
    |> foreign_key_constraint(:pool_id)
  end

  def status_changeset(worker, attrs) do
    worker
    |> cast(attrs, @status_fields)
    |> unique_constraint(:scaleway_server_id)
  end
end
