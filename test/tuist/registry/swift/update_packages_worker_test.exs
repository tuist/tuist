defmodule Tuist.Registry.Swift.Workers.UpdatePackagesWorkerTest do
  alias Tuist.VCS.Repositories.Content
  alias Tuist.VCS
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Environment
  alias Tuist.Registry.Swift.Packages
  alias TuistTestSupport.Fixtures.Registry.Swift.PackagesFixtures
  alias Tuist.Registry.Swift.Workers.UpdatePackagesWorker
  alias Tuist.Registry.Swift.Packages.Package

  setup do
    Environment
    |> stub(:github_token_update_packages, fn -> "github_token" end)

    :ok
  end

  test "creates missing packages" do
    # Given
    PackagesFixtures.package_fixture(scope: "Alamofire", name: "Alamofire")

    Packages
    |> expect(:create_missing_package_releases, fn
      %{
        package: %Package{
          scope: "onevcat",
          name: "Kingfisher",
          repository_full_handle: "onevcat/Kingfisher"
        },
        token: "github_token"
      } ->
        :ok
    end)

    VCS
    |> stub(:get_repository_content, fn _, _ ->
      {:ok,
       %Content{
         path: "packages.json",
         content:
           "[\n  \"https://github.com/Alamofire/Alamofire.git\",\n  \"https://github.com/onevcat/Kingfisher.git\"]"
       }}
    end)

    # When
    UpdatePackagesWorker.perform(%Oban.Job{})

    # Then
    assert Packages.get_package_by_scope_and_name(%{
             scope: "onevcat",
             name: "Kingfisher"
           }) != nil
  end

  test "creates missing package with a dot in its name" do
    # Given

    Packages
    |> expect(:create_missing_package_releases, fn
      %{
        package: %Package{
          scope: "stephenceilis",
          name: "SQLite_swift",
          repository_full_handle: "stephenceilis/SQLite.swift"
        },
        token: "github_token"
      } ->
        :ok
    end)

    VCS
    |> stub(:get_repository_content, fn _, _ ->
      {:ok,
       %Content{
         path: "packages.json",
         content: "[\n  \"https://github.com/stephenceilis/SQLite.swift.git\"]"
       }}
    end)

    # When
    UpdatePackagesWorker.perform(%Oban.Job{})

    # Then
    assert Packages.get_package_by_scope_and_name(%{
             scope: "stephenceilis",
             name: "SQLite_swift"
           }) != nil
  end
end
