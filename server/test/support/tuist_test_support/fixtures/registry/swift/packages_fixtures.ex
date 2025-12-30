defmodule TuistTestSupport.Fixtures.Registry.Swift.PackagesFixtures do
  @moduledoc false

  alias Tuist.Registry.Swift.Packages
  alias Tuist.Registry.Swift.Packages.PackageManifest
  alias Tuist.Registry.Swift.Packages.PackageRelease
  alias Tuist.Repo

  def package_fixture(opts \\ []) do
    scope = Keyword.get(opts, :scope, "#{TuistTestSupport.Utilities.unique_integer()}")
    name = Keyword.get(opts, :name, "#{TuistTestSupport.Utilities.unique_integer()}")
    repository_full_handle = Keyword.get(opts, :repository_full_handle, "#{scope}/#{name}")
    inserted_at = Keyword.get(opts, :inserted_at, DateTime.utc_now())
    updated_at = Keyword.get(opts, :updated_at, DateTime.utc_now())
    last_updated_releases_at = Keyword.get(opts, :last_updated_releases_at, DateTime.utc_now())
    preload = Keyword.get(opts, :preload, [])

    Packages.create_package(
      %{
        scope: scope,
        name: name,
        repository_full_handle: repository_full_handle
      },
      inserted_at: inserted_at,
      updated_at: updated_at,
      last_updated_releases_at: last_updated_releases_at,
      preload: preload
    )
  end

  def package_release_fixture(opts \\ []) do
    package_id =
      Keyword.get_lazy(opts, :package_id, fn ->
        package_fixture().id
      end)

    version = Keyword.get(opts, :version, "#{TuistTestSupport.Utilities.unique_integer()}")
    checksum = Keyword.get(opts, :checksum, "#{TuistTestSupport.Utilities.unique_integer()}")
    inserted_at = Keyword.get(opts, :inserted_at, DateTime.utc_now())

    %PackageRelease{}
    |> PackageRelease.create_changeset(%{
      package_id: package_id,
      checksum: checksum,
      version: version,
      inserted_at: inserted_at
    })
    |> Repo.insert!()
  end

  def package_manifest_fixture(opts \\ []) do
    package_release_id =
      Keyword.get_lazy(opts, :package_release_id, fn ->
        package_release_fixture().id
      end)

    swift_tools_version = Keyword.get(opts, :swift_tools_version)
    swift_version = Keyword.get(opts, :swift_version)

    %PackageManifest{}
    |> PackageManifest.create_changeset(%{
      package_release_id: package_release_id,
      swift_tools_version: swift_tools_version,
      swift_version: swift_version
    })
    |> Repo.insert!()
  end
end
