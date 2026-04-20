defmodule Tuist.Runners.OrchardWorkerPool do
  @moduledoc """
  A per-account pool of Scaleway bare-metal Macs.

  Callers set **spec** fields (`desired_size`, `enabled`, Scaleway config). The
  reconciler owns **status** fields (`last_reconciled_at` and derived counts).
  Keep the two sets apart so this schema maps cleanly onto a future CRD with
  `spec` and `status` subresources.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.Accounts.Account
  alias Tuist.Runners.OrchardWorker

  @primary_key {:id, UUIDv7, autogenerate: true}
  @foreign_key_type UUIDv7

  @spec_fields [
    :name,
    :enabled,
    :desired_size,
    :scaleway_zone,
    :scaleway_server_type,
    :scaleway_os
  ]

  @name_regex ~r/^[a-z0-9][a-z0-9-]{0,62}[a-z0-9]$/

  schema "orchard_worker_pools" do
    field :name, :string
    field :enabled, :boolean, default: true
    field :desired_size, :integer, default: 0
    field :scaleway_zone, :string
    field :scaleway_server_type, :string
    field :scaleway_os, :string
    field :last_reconciled_at, :utc_datetime

    belongs_to :account, Account, type: :integer

    has_many :workers, OrchardWorker, foreign_key: :pool_id

    timestamps(type: :utc_datetime)
  end

  def spec_fields, do: @spec_fields

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:account_id | @spec_fields])
    |> validate_required([
      :account_id,
      :name,
      :scaleway_zone,
      :scaleway_server_type,
      :scaleway_os
    ])
    |> validate_format(:name, @name_regex, message: "must be lowercase alphanumeric with hyphens, 2-64 chars")
    |> validate_number(:desired_size, greater_than_or_equal_to: 0, less_than_or_equal_to: 50)
    |> unique_constraint([:account_id, :name])
    |> foreign_key_constraint(:account_id)
  end

  def spec_changeset(pool, attrs) do
    pool
    |> cast(attrs, @spec_fields)
    |> validate_number(:desired_size, greater_than_or_equal_to: 0, less_than_or_equal_to: 50)
  end

  def status_changeset(pool, attrs) do
    cast(pool, attrs, [:last_reconciled_at])
  end
end
