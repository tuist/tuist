defmodule Tuist.Registry.Swift.Workers.SyncPackagesWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Environment
  alias Tuist.Registry.Swift.Packages
  alias Tuist.Registry.Swift.Packages.Package
  alias Tuist.Registry.Swift.Workers.SyncPackagesWorker
  alias Tuist.Time
  alias Tuist.VCS
  alias Tuist.VCS.Repositories.Content
  alias TuistTestSupport.Fixtures.Registry.Swift.PackagesFixtures

  setup do
    stub(Environment, :github_token_update_packages, fn -> "packages_token" end)
    stub(Environment, :github_token_update_package_releases, fn -> "releases_token" end)
    stub(Time, :utc_now, fn -> ~U[2024-07-31 00:03:00Z] end)

    stub(Oban, :insert!, fn %Ecto.Changeset{} = changeset ->
      assert changeset.data.__struct__ == Oban.Job
      assert changeset.changes.worker == "Tuist.Registry.Swift.Workers.CreatePackageReleaseWorker"
      changeset
    end)

    :ok
  end

  describe "perform/1" do
    test "syncs both new packages and existing package releases by default" do
      # Given - existing package needing updates
      _package =
        PackagesFixtures.package_fixture(
          scope: "Alamofire",
          name: "Alamofire",
          last_updated_releases_at: ~U[2024-07-31 00:00:00Z],
          preload: [:package_releases]
        )

      # Mock SwiftPackageIndex response
      stub(VCS, :get_repository_content, fn _, _ ->
        {:ok,
         %Content{
           path: "packages.json",
           content: ~s([\n  "https://github.com/Alamofire/Alamofire.git",\n  "https://github.com/onevcat/Kingfisher.git"])
         }}
      end)

      # Mock missing versions - will be called for both new package and existing package
      stub(Packages, :get_missing_package_versions, fn
        %{package: %Package{scope: "Alamofire", name: "Alamofire"}, token: "releases_token"} ->
          [%{scope: "Alamofire", name: "Alamofire", version: "5.10.0"}]

        %{package: %Package{scope: "onevcat", name: "Kingfisher"}, token: "releases_token"} ->
          [%{scope: "onevcat", name: "Kingfisher", version: "7.0.0"}]
      end)

      # When
      result = SyncPackagesWorker.perform(%Oban.Job{args: %{limit: 10}})

      # Then
      assert result == :ok

      # Verify new package was created
      assert {:ok, _new_package} =
               Packages.get_package_by_scope_and_name(%{scope: "onevcat", name: "Kingfisher"})

      # Verify existing package timestamp was updated
      assert {:ok, updated_package} =
               Packages.get_package_by_scope_and_name(%{scope: "Alamofire", name: "Alamofire"})

      assert updated_package.last_updated_releases_at == ~U[2024-07-31 00:03:00Z]
    end

    test "only syncs packages when update_packages=true and update_releases=false" do
      # Given
      stub(VCS, :get_repository_content, fn _, _ ->
        {:ok,
         %Content{
           path: "packages.json",
           content: ~s([\n  "https://github.com/onevcat/Kingfisher.git"])
         }}
      end)

      expect(Packages, :get_missing_package_versions, 1, fn
        %{package: %Package{scope: "onevcat", name: "Kingfisher"}, token: "releases_token"} ->
          [%{scope: "onevcat", name: "Kingfisher", version: "7.0.0"}]
      end)

      # When
      result =
        SyncPackagesWorker.perform(%Oban.Job{
          args: %{update_packages: true, update_releases: false}
        })

      # Then
      assert result == :ok
      assert {:ok, _} = Packages.get_package_by_scope_and_name(%{scope: "onevcat", name: "Kingfisher"})
    end

    test "only syncs existing package releases when update_packages=false and update_releases=true" do
      # Given - existing package needing updates
      PackagesFixtures.package_fixture(
        scope: "Alamofire",
        name: "Alamofire",
        last_updated_releases_at: ~U[2024-07-31 00:00:00Z],
        preload: [:package_releases]
      )

      expect(Packages, :get_missing_package_versions, 1, fn
        %{package: %Package{scope: "Alamofire", name: "Alamofire"}, token: "releases_token"} ->
          [%{scope: "Alamofire", name: "Alamofire", version: "5.10.0"}]
      end)

      # When
      result =
        SyncPackagesWorker.perform(%Oban.Job{
          args: %{limit: 10, update_packages: false, update_releases: true}
        })

      # Then
      assert result == :ok

      # Verify existing package timestamp was updated
      assert {:ok, updated_package} =
               Packages.get_package_by_scope_and_name(%{scope: "Alamofire", name: "Alamofire"})

      assert updated_package.last_updated_releases_at == ~U[2024-07-31 00:03:00Z]
    end

    test "removes packages no longer present in SwiftPackageIndex" do
      # Given - existing package that will be removed
      existing_package =
        PackagesFixtures.package_fixture(
          scope: "ToBeRemoved",
          name: "Package",
          repository_full_handle: "ToBeRemoved/Package"
        )

      stub(VCS, :get_repository_content, fn _, _ ->
        {:ok,
         %Content{
           path: "packages.json",
           content: ~s([\n  "https://github.com/onevcat/Kingfisher.git"])
         }}
      end)

      expect(Packages, :get_missing_package_versions, 1, fn
        %{package: %Package{scope: "onevcat", name: "Kingfisher"}, token: "releases_token"} ->
          [%{scope: "onevcat", name: "Kingfisher", version: "7.0.0"}]
      end)

      # When
      result =
        SyncPackagesWorker.perform(%Oban.Job{
          args: %{update_packages: true, update_releases: false}
        })

      # Then
      assert result == :ok

      # Verify removed package is gone
      assert {:error, :not_found} =
               Packages.get_package_by_scope_and_name(%{
                 scope: existing_package.scope,
                 name: existing_package.name
               })

      # Verify new package was created
      assert {:ok, _} = Packages.get_package_by_scope_and_name(%{scope: "onevcat", name: "Kingfisher"})
    end

    test "handles packages with dots in names" do
      # Given
      stub(VCS, :get_repository_content, fn _, _ ->
        {:ok,
         %Content{
           path: "packages.json",
           content: ~s([\n  "https://github.com/stephenceilis/SQLite.swift.git"])
         }}
      end)

      expect(Packages, :get_missing_package_versions, 1, fn
        %{
          package: %Package{scope: "stephenceilis", name: "SQLite_swift"},
          token: "releases_token"
        } ->
          [%{scope: "stephenceilis", name: "SQLite_swift", version: "0.15.0"}]
      end)

      # When
      result =
        SyncPackagesWorker.perform(%Oban.Job{
          args: %{update_packages: true, update_releases: false}
        })

      # Then
      assert result == :ok

      # Verify package with converted name was created
      assert {:ok, _} =
               Packages.get_package_by_scope_and_name(%{
                 scope: "stephenceilis",
                 name: "SQLite_swift"
               })
    end

    test "limits existing package releases processing" do
      # Given - multiple existing packages, but limit should apply
      for i <- 1..5 do
        PackagesFixtures.package_fixture(
          scope: "Package#{i}",
          name: "Test",
          last_updated_releases_at: ~U[2024-07-31 00:00:00Z],
          preload: [:package_releases]
        )
      end

      expect(Packages, :get_missing_package_versions, 2, fn
        %{package: %Package{scope: scope}, token: "releases_token"} ->
          [%{scope: scope, name: "Test", version: "1.0.0"}]
      end)

      # When - limit to 2 packages
      result =
        SyncPackagesWorker.perform(%Oban.Job{
          args: %{limit: 2, update_packages: false, update_releases: true}
        })

      # Then
      assert result == :ok
    end

    test "does nothing when both update flags are false" do
      # Given
      PackagesFixtures.package_fixture(
        scope: "Alamofire",
        name: "Alamofire",
        preload: [:package_releases]
      )

      # When
      result =
        SyncPackagesWorker.perform(%Oban.Job{
          args: %{update_packages: false, update_releases: false}
        })

      # Then
      assert result == :ok
      # No expectations set, so no functions should be called
    end

    test "filters packages using allowlist from args" do
      # Given
      stub(VCS, :get_repository_content, fn _, _ ->
        {:ok,
         %Content{
           path: "packages.json",
           content:
             ~s([\n  "https://github.com/tuist/XcodeGraph.git",\n  "https://github.com/tuist/Path.git",\n  "https://github.com/Alamofire/Alamofire.git",\n  "https://github.com/onevcat/Kingfisher.git"])
         }}
      end)

      # Only expect calls for tuist packages
      expect(Packages, :get_missing_package_versions, 2, fn
        %{package: %Package{scope: "tuist"}, token: "releases_token"} ->
          []
      end)

      # When - pass allowlist via args
      result =
        SyncPackagesWorker.perform(%Oban.Job{
          args: %{update_packages: true, update_releases: false, allowlist: ["tuist/*"]}
        })

      # Then
      assert result == :ok

      # Verify only tuist packages were created
      assert {:ok, _} = Packages.get_package_by_scope_and_name(%{scope: "tuist", name: "XcodeGraph"})
      assert {:ok, _} = Packages.get_package_by_scope_and_name(%{scope: "tuist", name: "Path"})

      # Verify other packages were not created
      assert {:error, :not_found} =
               Packages.get_package_by_scope_and_name(%{scope: "Alamofire", name: "Alamofire"})

      assert {:error, :not_found} =
               Packages.get_package_by_scope_and_name(%{scope: "onevcat", name: "Kingfisher"})
    end

    test "allowlist supports exact matches and wildcard patterns" do
      # Given
      stub(VCS, :get_repository_content, fn _, _ ->
        {:ok,
         %Content{
           path: "packages.json",
           content:
             ~s([\n  "https://github.com/tuist/XcodeGraph.git",\n  "https://github.com/tuist/Path.git",\n  "https://github.com/Alamofire/Alamofire.git",\n  "https://github.com/Alamofire/AlamofireImage.git"])
         }}
      end)

      # Expect calls for specific packages
      expect(Packages, :get_missing_package_versions, 3, fn
        %{package: %Package{}, token: "releases_token"} ->
          []
      end)

      # When - use both exact match and wildcard
      result =
        SyncPackagesWorker.perform(%Oban.Job{
          args: %{
            update_packages: true,
            update_releases: false,
            allowlist: ["tuist/*", "Alamofire/Alamofire"]
          }
        })

      # Then
      assert result == :ok

      # Verify wildcard matched packages
      assert {:ok, _} = Packages.get_package_by_scope_and_name(%{scope: "tuist", name: "XcodeGraph"})
      assert {:ok, _} = Packages.get_package_by_scope_and_name(%{scope: "tuist", name: "Path"})

      # Verify exact match
      assert {:ok, _} = Packages.get_package_by_scope_and_name(%{scope: "Alamofire", name: "Alamofire"})

      # Verify non-matching package was not created
      assert {:error, :not_found} =
               Packages.get_package_by_scope_and_name(%{scope: "Alamofire", name: "AlamofireImage"})
    end

    test "empty allowlist allows all packages" do
      # Given
      stub(VCS, :get_repository_content, fn _, _ ->
        {:ok,
         %Content{
           path: "packages.json",
           content: ~s([\n  "https://github.com/Alamofire/Alamofire.git",\n  "https://github.com/onevcat/Kingfisher.git"])
         }}
      end)

      expect(Packages, :get_missing_package_versions, 2, fn
        %{package: %Package{}, token: "releases_token"} ->
          []
      end)

      # When - pass empty allowlist
      result =
        SyncPackagesWorker.perform(%Oban.Job{
          args: %{update_packages: true, update_releases: false, allowlist: []}
        })

      # Then
      assert result == :ok

      # Verify all packages were created
      assert {:ok, _} = Packages.get_package_by_scope_and_name(%{scope: "Alamofire", name: "Alamofire"})
      assert {:ok, _} = Packages.get_package_by_scope_and_name(%{scope: "onevcat", name: "Kingfisher"})
    end

    test "nil allowlist allows all packages" do
      # Given
      stub(VCS, :get_repository_content, fn _, _ ->
        {:ok,
         %Content{
           path: "packages.json",
           content: ~s([\n  "https://github.com/Alamofire/Alamofire.git",\n  "https://github.com/onevcat/Kingfisher.git"])
         }}
      end)

      expect(Packages, :get_missing_package_versions, 2, fn
        %{package: %Package{}, token: "releases_token"} ->
          []
      end)

      # When - no allowlist specified
      result =
        SyncPackagesWorker.perform(%Oban.Job{
          args: %{update_packages: true, update_releases: false}
        })

      # Then
      assert result == :ok

      # Verify all packages were created
      assert {:ok, _} = Packages.get_package_by_scope_and_name(%{scope: "Alamofire", name: "Alamofire"})
      assert {:ok, _} = Packages.get_package_by_scope_and_name(%{scope: "onevcat", name: "Kingfisher"})
    end
  end
end
