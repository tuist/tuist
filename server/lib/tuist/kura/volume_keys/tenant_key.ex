defmodule Tuist.Kura.VolumeKeys.TenantKey do
  @moduledoc """
  One version of a Kura tenant key: the wrapped shares whose plaintexts,
  concatenated in order, are the input keying material every volume
  passphrase of the account is derived from. At most one version per account
  is `:active`; `:retired` versions stay unwrappable for volumes built under
  them. Deleting the account deletes its rows, which makes its volumes
  unreadable.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.Accounts.Account

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "kura_tenant_keys" do
    belongs_to :account, Account
    field :version, :integer
    field :shares, {:array, :map}
    field :state, Ecto.Enum, values: [:active, :retired], default: :active

    timestamps(type: :utc_datetime)
  end

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:account_id, :version, :shares, :state])
    |> validate_required([:account_id, :version, :shares, :state])
    |> validate_number(:version, greater_than: 0)
    |> validate_length(:shares, min: 1)
    |> foreign_key_constraint(:account_id)
    |> unique_constraint([:account_id, :version])
    |> unique_constraint(:account_id, name: :kura_tenant_keys_one_active_per_account_index)
  end
end
