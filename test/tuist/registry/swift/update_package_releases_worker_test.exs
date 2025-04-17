defmodule Tuist.Registry.Swift.Workers.UpdatePackageReleasesWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Environment
  alias Tuist.Registry.Swift.Packages
  alias Tuist.Registry.Swift.Workers.UpdatePackageReleasesWorker
  alias Tuist.Time
  alias TuistTestSupport.Fixtures.Registry.Swift.PackagesFixtures

  setup do
    stub(Environment, :github_token_update_package_releases, fn -> "github_token" end)
    :ok
  end

  test "updates two packages that have not been updated for the longest time" do
    # Given
    package_one =
      PackagesFixtures.package_fixture(
        last_updated_releases_at: ~U[2024-07-31 00:00:00Z],
        preload: [:package_releases]
      )

    package_two =
      PackagesFixtures.package_fixture(
        last_updated_releases_at: ~U[2024-07-31 00:01:00Z],
        preload: [:package_releases]
      )

    _package_three =
      PackagesFixtures.package_fixture(last_updated_releases_at: ~U[2024-07-31 00:02:00Z])

    package_four =
      PackagesFixtures.package_fixture(
        last_updated_releases_at: nil,
        preload: [:package_releases]
      )

    stub(Time, :utc_now, fn -> ~U[2024-07-31 00:03:00Z] end)

    stub(Packages, :create_missing_package_releases, fn
      %{package: ^package_one, token: "github_token"} -> :ok
      %{package: ^package_two, token: "github_token"} -> :ok
      %{package: ^package_four, token: "github_token"} -> :ok
    end)

    # When
    UpdatePackageReleasesWorker.perform(%Oban.Job{args: %{limit: 3}})

    # Then
    assert Packages.get_package_by_scope_and_name(%{
             scope: package_one.scope,
             name: package_one.name
           }).last_updated_releases_at == ~U[2024-07-31 00:03:00Z]

    assert Packages.get_package_by_scope_and_name(%{
             scope: package_two.scope,
             name: package_two.name
           }).last_updated_releases_at == ~U[2024-07-31 00:03:00Z]

    assert Packages.get_package_by_scope_and_name(%{
             scope: package_four.scope,
             name: package_four.name
           }).last_updated_releases_at == ~U[2024-07-31 00:03:00Z]
  end
end
