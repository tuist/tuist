defmodule Tuist.Registry.Swift.Packages.Package do
  @moduledoc """
  A module that represents a Swift package.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.Registry.Swift.Packages.PackageRelease

  @derive {
    Flop.Schema,
    filterable: [:scope, :name], sortable: [:last_updated_releases_at]
  }

  @primary_key {:id, UUIDv7, autogenerate: true}
  schema "packages" do
    field :scope, :string
    field :name, :string
    field :repository_full_handle, :string
    field :last_updated_releases_at, :utc_datetime

    has_many(:package_releases, PackageRelease)

    timestamps(type: :utc_datetime)
  end

  def create_changeset(token, attrs) do
    token
    |> cast(attrs, [
      :scope,
      :name,
      :repository_full_handle,
      :inserted_at,
      :updated_at,
      :last_updated_releases_at
    ])
    |> validate_required([:scope, :name, :repository_full_handle])
    |> unique_constraint([:scope, :name])
  end

  def update_changeset(package, attrs) do
    cast(package, attrs, [:last_updated_releases_at])
  end
end
