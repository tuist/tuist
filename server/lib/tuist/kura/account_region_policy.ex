defmodule Tuist.Kura.AccountRegionPolicy do
  @moduledoc """
  A versioned explicit Kura service-region assignment for an account.

  The latest row whose `superseded_at` is empty is the current assignment.
  Reassignments append a new version so the previous region, actor, and reason
  remain available for audit and rollback.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.Accounts.Account
  alias Tuist.Accounts.User

  # The regions an operator may pin a paid account to.
  #
  # `us-west` is here and nowhere else: `accounts.region` is `all | europe |
  # usa`, `usa` derives to `us-east`, and `all` defaults to `us-east`, so no
  # storage-region preference ever resolves to it. It is opted into per account
  # for latency rather than derived. Air can never land there either, because
  # Air resolves from the storage-region preference and never from an
  # assignment.
  #
  # Narrower than the region catalog and than the column's CHECK constraint:
  # the Air pools serve one plan on hardware sized for it, so they are never an
  # assignment target.
  @service_regions ["us-east", "eu-central", "us-west"]

  @primary_key {:id, UUIDv7, autogenerate: true}
  schema "kura_account_region_policies" do
    field :service_region, :string
    field :version, :integer
    field :reason, :string
    field :superseded_at, :utc_datetime

    belongs_to :account, Account
    belongs_to :assigned_by_user, User

    timestamps(type: :utc_datetime)
  end

  def service_regions, do: @service_regions

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [
      :account_id,
      :service_region,
      :version,
      :reason,
      :assigned_by_user_id
    ])
    |> validate_required([
      :account_id,
      :service_region,
      :version,
      :reason,
      :assigned_by_user_id
    ])
    |> validate_inclusion(:service_region, @service_regions)
    |> validate_number(:version, greater_than: 0)
    |> validate_length(:reason, min: 1, max: 1_000)
    |> check_constraint(:version, name: :kura_account_region_policies_version_positive)
    |> foreign_key_constraint(:account_id)
    |> foreign_key_constraint(:assigned_by_user_id)
    |> unique_constraint([:account_id, :version])
    |> unique_constraint(:account_id,
      name: :kura_account_region_policies_active_account_index,
      message: "already has a current service-region assignment"
    )
  end
end
