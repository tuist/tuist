defmodule Tuist.Registry.Swift.Packages.PackageDownloadEvent do
  @moduledoc ~S"""
  A module that represents the package download event.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.Accounts.Account
  alias Tuist.Registry.Swift.Packages.PackageRelease

  @primary_key {:id, UUIDv7, autogenerate: true}
  schema "package_download_events" do
    belongs_to :account, Account
    belongs_to :package_release, PackageRelease, type: UUIDv7

    timestamps(type: :utc_datetime)
  end

  def create_changeset(token, attrs) do
    token
    |> cast(attrs, [
      :account_id,
      :package_release_id
    ])
    |> validate_required([:account_id, :package_release_id])
  end
end
