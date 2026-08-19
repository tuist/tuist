defmodule Tuist.Kura.LifecycleOperatorAction do
  @moduledoc """
  A record that an operator archived or unarchived an account-region instance
  by hand, overriding the demand-driven lifecycle.

  Only operator actions are recorded. The sweep's own transitions are already
  visible in the instance status, the lifecycle clocks, and the telemetry; this
  table exists to answer who reclaimed a particular account's cache, which
  those cannot.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.Accounts.Account
  alias Tuist.Accounts.User

  @actions [archive: 0, unarchive: 1]

  @primary_key {:id, UUIDv7, autogenerate: true}
  schema "kura_lifecycle_operator_actions" do
    field :service_region, :string
    field :action, Ecto.Enum, values: @actions

    belongs_to :account, Account
    belongs_to :performed_by_user, User

    timestamps(type: :utc_datetime)
  end

  def actions, do: Keyword.keys(@actions)

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:account_id, :service_region, :action, :performed_by_user_id])
    |> validate_required([:account_id, :service_region, :action])
    |> validate_inclusion(:action, actions())
    |> foreign_key_constraint(:account_id)
    |> foreign_key_constraint(:performed_by_user_id)
  end
end
