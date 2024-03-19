defmodule TuistCloud.Accounts.Account do
  @moduledoc ~S"""
  A module that represents the accounts table.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          name: String.t(),
          owner_type: String.t(),
          owner_id: integer()
        }

  schema "accounts" do
    field :plan, Ecto.Enum, values: [enterprise: 1]
    field :name, :string
    field :owner_type, :string
    field :owner_id, :integer
    field :cache_upload_event_count, :integer
    field :cache_download_event_count, :integer

    timestamps(inserted_at: :created_at)
  end

  def create_changeset(account, attrs) do
    account
    |> cast(attrs, [:name, :owner_type, :owner_id])
    |> validate_required([:name, :owner_type, :owner_id])
    |> validate_inclusion(:owner_type, ["User", "Organization"])
    |> unique_constraint(:name)
    |> unique_constraint([:owner_id, :owner_type])
  end
end
