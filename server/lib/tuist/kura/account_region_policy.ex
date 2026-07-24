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

  @service_regions ["us-east", "eu-central"]

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
