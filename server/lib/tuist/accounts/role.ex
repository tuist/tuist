defmodule Tuist.Accounts.Role do
  @moduledoc ~S"""
  A module that represents the roles table.
  """
  use Ecto.Schema

  import Ecto.Changeset

  @names ~w(admin user viewer)

  schema "roles" do
    field :name, :string
    field :resource_type, :string
    field :resource_id, :integer
    # credo:disable-for-next-line Credo.Checks.TimestampsType
    timestamps(inserted_at: :created_at)
  end

  @doc """
  The role names an organization membership can hold. `viewer` is read-only:
  it is granted inside read actions in `Tuist.Authorization` and nowhere else.
  """
  def names, do: @names

  def create_changeset(role, attrs) do
    role
    |> cast(attrs, [:name, :resource_type, :resource_id])
    |> validate_required([:name, :resource_type, :resource_id])
    |> validate_inclusion(:name, @names)
  end
end
