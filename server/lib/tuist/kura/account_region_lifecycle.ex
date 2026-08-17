defmodule Tuist.Kura.AccountRegionLifecycle do
  @moduledoc """
  Demand and archival bookkeeping for one account-region Kura instance.

  Identity is `(account, service_region)`: one Kura instance serves every
  project the account has in that region, so `last_cache_demand_at` is the
  latest qualifying cache request across those projects, not a per-project
  clock.

  The row outlives the `kura_servers` row it describes. That is the point:
  an archived account has no server, and its demand timestamp is what the
  next cache request compares against to decide whether to cold-provision.

  `keep_warm` is the minimum representation the lifecycle needs to honour an
  account-region keep-warm exception: while set, the instance is never drained
  and never counted as archival-eligible. The full versioned override record
  (ownership, review date, expiry, capacity preflight, rollback) is separate
  work.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.Accounts.Account

  @primary_key {:id, UUIDv7, autogenerate: true}
  schema "kura_account_region_lifecycles" do
    field :service_region, :string
    field :last_cache_demand_at, :utc_datetime
    field :keep_warm, :boolean, default: false
    field :drain_started_at, :utc_datetime
    field :teardown_started_at, :utc_datetime
    field :archived_at, :utc_datetime
    field :last_reclaimed_bytes, :integer
    field :last_drain_duration_ms, :integer
    field :last_returned_at, :utc_datetime

    belongs_to :account, Account

    timestamps(type: :utc_datetime)
  end

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:account_id, :service_region, :last_cache_demand_at, :keep_warm])
    |> validate_required([:account_id, :service_region, :last_cache_demand_at])
    |> foreign_key_constraint(:account_id)
    |> unique_constraint([:account_id, :service_region])
  end

  @doc """
  Records the lifecycle-phase transitions the archival sweep drives:
  entering drain-pending, issuing teardown, completing archival, and
  cancelling or cold-returning back to a served instance.
  """
  def phase_changeset(%__MODULE__{} = lifecycle, attrs) do
    cast(lifecycle, attrs, [
      :drain_started_at,
      :teardown_started_at,
      :archived_at,
      :last_reclaimed_bytes,
      :last_drain_duration_ms,
      :last_returned_at
    ])
  end

  @doc "Sets or clears the account-region keep-warm exception."
  def keep_warm_changeset(%__MODULE__{} = lifecycle, attrs) do
    lifecycle
    |> cast(attrs, [:keep_warm])
    |> validate_required([:keep_warm])
  end
end
