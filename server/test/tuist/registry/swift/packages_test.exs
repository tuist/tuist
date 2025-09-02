defmodule Tuist.Registry.Swift.PackagesTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Registry.Swift.Packages
  alias Tuist.Repo
  alias Tuist.Storage
  alias Tuist.VCS
  alias Tuist.VCS.Repositories.Tag
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.Registry.Swift.PackagesFixtures

  describe "create_package/2" do
    test "creates a new package" do
      # When
      package =
        Packages.create_package(%{
          scope: "Scope",
          name: "Name",
          repository_full_handle: "Scope/Name"
        })

      # Then
      assert package.scope == "Scope"
      assert package.name == "Name"
      assert package.repository_full_handle == "Scope/Name"
    end
  end

  describe "delete_package/1" do
    test "deletes a package" do
      # Given
      package = PackagesFixtures.package_fixture(scope: "Scope", name: "Name")

      # When
      Packages.delete_package(package)

      # Then
      assert Packages.get_package_by_scope_and_name(%{scope: "Scope", name: "Name"}) == nil
    end
  end

  describe "all_packages/1" do
    test "returns all packages" do
      # Given
      package_one =
        PackagesFixtures.package_fixture(
          scope: "ScopeOne",
          name: "NameOne",
          preload: [:package_releases]
        )

      package_two =
        PackagesFixtures.package_fixture(
          scope: "ScopeTwo",
          name: "NameTwo",
          preload: [:package_releases]
        )

      # When
      got = Packages.all_packages(preload: [:package_releases])

      # Then
      assert Enum.sort_by(got, & &1.scope) == [package_one, package_two]
    end
  end

  describe "get_package_by_scope_and_name/1" do
    test "returns a package by scope and name" do
      # Given
      package = PackagesFixtures.package_fixture(scope: "Scope", name: "Name")

      # When
      got = Packages.get_package_by_scope_and_name(%{scope: "Scope", name: "Name"})

      # Then
      assert got == package
    end

    test "returns nil when the package does not exist" do
      # When
      got = Packages.get_package_by_scope_and_name(%{scope: "Scope", name: "Name"})

      # Then
      assert got == nil
    end
  end

  describe "get_package_scope_and_name_from_repository_full_handle/1" do
    test "returns scope and name" do
      # When
      got = Packages.get_package_scope_and_name_from_repository_full_handle("Scope/Name")

      # Then
      assert got == %{scope: "Scope", name: "Name", repository_full_handle: "Scope/Name"}
    end
  end

  describe "get_missing_package_versions/1" do
    test "returns missing package versions" do
      # Given
      package =
        PackagesFixtures.package_fixture(
          scope: "Alamofire",
          name: "Alamofire"
        )

      PackagesFixtures.package_release_fixture(package_id: package.id, version: "5.10.1")

      stub(VCS, :get_tags, fn _ ->
        [
          %Tag{name: "5.10.2"},
          %Tag{name: "5.10.1"},
          %Tag{name: "5.10.0"},
          %Tag{name: "5.11"},
          %Tag{name: "tag@5.0.0"}
        ]
      end)

      # When
      got =
        Packages.get_missing_package_versions(%{
          package: Repo.preload(package, :package_releases),
          token: "github_token"
        })

      # Then
      assert Enum.map(got, & &1.version) == [
               "5.10.2",
               "5.10.0",
               "5.11"
             ]

      assert Enum.all?(got, &(&1.scope == "Alamofire"))
      assert Enum.all?(got, &(&1.name == "Alamofire"))
    end

    test "skips package version with a v prefix when its semantic variant has already been created" do
      # Given
      package =
        PackagesFixtures.package_fixture(
          scope: "Alamofire",
          name: "Alamofire"
        )

      PackagesFixtures.package_release_fixture(package_id: package.id, version: "5.10.2")

      stub(VCS, :get_tags, fn _ ->
        [
          %Tag{name: "v5.10.2"},
          %Tag{name: "5.10.2"}
        ]
      end)

      # When
      got =
        Packages.get_missing_package_versions(%{
          package: Repo.preload(package, :package_releases),
          token: "github_token"
        })

      # Then
      assert got == []
    end

    test "returns versions in v-prefixed format when that's the tag format" do
      # Given
      package =
        PackagesFixtures.package_fixture(
          scope: "Alamofire",
          name: "Alamofire"
        )

      stub(VCS, :get_tags, fn _ ->
        [
          %Tag{name: "v5.10.2"}
        ]
      end)

      # When
      got =
        Packages.get_missing_package_versions(%{
          package: Repo.preload(package, :package_releases),
          token: "github_token"
        })

      # Then
      assert Enum.map(got, & &1.version) == ["v5.10.2"]
      assert Enum.all?(got, &(&1.scope == "Alamofire"))
      assert Enum.all?(got, &(&1.name == "Alamofire"))
    end

    test "handles pre-release versions" do
      # Given
      package =
        PackagesFixtures.package_fixture(
          scope: "Alamofire",
          name: "Alamofire"
        )

      stub(VCS, :get_tags, fn _ ->
        [
          %Tag{name: "5.10.2-beta"},
          %Tag{name: "5.10.2-beta.1"},
          %Tag{name: "v5.10.2-beta.2"},
          %Tag{name: "5.10.2-beta-3"}
        ]
      end)

      # When
      got =
        Packages.get_missing_package_versions(%{
          package: Repo.preload(package, :package_releases),
          token: "github_token"
        })

      # Then
      assert Enum.map(got, & &1.version) == [
               "5.10.2-beta",
               "5.10.2-beta.1",
               "v5.10.2-beta.2",
               "5.10.2-beta-3"
             ]
    end

    test "filters out dev versions" do
      # Given
      package =
        PackagesFixtures.package_fixture(
          scope: "Alamofire",
          name: "Alamofire"
        )

      stub(VCS, :get_tags, fn _ ->
        [
          %Tag{name: "5.10.2"},
          %Tag{name: "0.9.3-dev1985"},
          %Tag{name: "1.0.0-dev123"}
        ]
      end)

      # When
      got =
        Packages.get_missing_package_versions(%{
          package: Repo.preload(package, :package_releases),
          token: "github_token"
        })

      # Then
      assert Enum.map(got, & &1.version) == ["5.10.2"]
    end
  end

  describe "paginated_packages/1" do
    test "lists first page of packages" do
      # Givne
      package_one =
        PackagesFixtures.package_fixture(
          updated_at: ~U[2024-07-31 00:00:00Z],
          preload: [:package_releases]
        )

      package_two =
        PackagesFixtures.package_fixture(
          updated_at: ~U[2024-07-31 00:01:00Z],
          preload: [:package_releases]
        )

      _package_three = PackagesFixtures.package_fixture(updated_at: ~U[2024-07-31 00:02:00Z])

      # When
      {got_first_page, _got_meta_first_page} =
        Packages.paginated_packages(
          %{
            first: 2,
            order_by: [:last_updated_releases_at],
            order_direction: :asc
          },
          preload: [:package_releases]
        )

      # Then
      assert got_first_page == [package_one, package_two]
    end
  end

  describe "update_package/2" do
    test "updates last_updated_releases_at" do
      # Given
      package = PackagesFixtures.package_fixture()
      new_attrs = %{last_updated_releases_at: ~U[2024-07-31 00:03:00Z]}

      # When
      {:ok, updated_package} = Packages.update_package(package, new_attrs)

      # Then
      assert updated_package.last_updated_releases_at == ~U[2024-07-31 00:03:00Z]
    end
  end

  describe "get_package_release_by_version/1" do
    test "returns package release" do
      # Given
      package = PackagesFixtures.package_fixture()

      package_release =
        PackagesFixtures.package_release_fixture(package_id: package.id, version: "5.10.1")

      # When
      got = Packages.get_package_release_by_version(%{package: package, version: "5.10.1"})

      # Then
      assert got == package_release
    end

    test "returns nil when the package release does not exist" do
      # Given
      package = PackagesFixtures.package_fixture()

      # When
      got = Packages.get_package_release_by_version(%{package: package, version: "5.10.1"})

      # Then
      assert got == nil
    end
  end

  describe "package_manifest_as_string/1" do
    test "returns the package manifest as string" do
      # Given
      stub(Storage, :object_exists?, fn _ -> true end)

      stub(Storage, :get_object_as_string, fn _ ->
        """
        // swift-tools-version:5.9
        import PackageDescription

        let package = Package(
            name: "xcbeautify",
            products: [
                .executable(name: "xcbeautify", targets: ["xcbeautify"]),
                .library(name: "XcbeautifyLib", targets: ["XcbeautifyLib"]),
            ],
            dependencies: [
                .package(
                    url: "https://github.com/apple/swift-argument-parser.git",
                    .upToNextMinor(from: "1.5.0")
                ),
                .package(
                    url: "https://github.com/getGuaka/Colorizer.git",
                    .upToNextMinor(from: "0.2.1")
                ),
                .package(url: "https://github.com/SwiftGen/SwiftGen", .upToNextMinor(from: "0.2.1")),
                .package(
                    url: "https://github.com/MaxDesiatov/XMLCoder.git",
                    .upToNextMinor(from: "0.17.1")
                ),
                // Invalid commented out package
                //        .package(name: "ExportDeviceKit", url: "./Packages/ExportDeviceKit", branch: "master"),
            ],
            targets: [
                .executableTarget(
                    name: "xcbeautify",
                    dependencies: [
                        "XcbeautifyLib",
                        "SwiftGen",
                        .product(name: "ArgumentParser", package: "swift-argument-parser"),
                    ]
                ),
                .target(
                    name: "XcbeautifyLib",
                    dependencies: [
                        "Colorizer",
                        .product(name: "XMLCoder", package: "XMLCoder"),
                    ]
                ),
            ]
        )
        """
      end)

      # When
      got =
        Packages.package_manifest_as_string(%{scope: "My", name: "Package", version: "5.10.1"})

      # Then
      assert got ==
               {:ok,
                """
                // swift-tools-version:5.9
                import PackageDescription

                let package = Package(
                    name: "xcbeautify",
                    products: [
                        .executable(name: "xcbeautify", targets: ["xcbeautify"]),
                        .library(name: "XcbeautifyLib", targets: ["XcbeautifyLib"]),
                    ],
                    dependencies: [
                        .package(
                            url: "https://github.com/apple/swift-argument-parser.git",
                            .upToNextMinor(from: "1.5.0")
                        ),
                        .package(
                            url: "https://github.com/getGuaka/Colorizer.git",
                            .upToNextMinor(from: "0.2.1")
                        ),
                        .package(url: "https://github.com/SwiftGen/SwiftGen", .upToNextMinor(from: "0.2.1")),
                        .package(
                            url: "https://github.com/MaxDesiatov/XMLCoder.git",
                            .upToNextMinor(from: "0.17.1")
                        ),
                        // Invalid commented out package
                        //        .package(name: "ExportDeviceKit", url: "./Packages/ExportDeviceKit", branch: "master"),
                    ],
                    targets: [
                        .executableTarget(
                            name: "xcbeautify",
                            dependencies: [
                                "XcbeautifyLib",
                                .product(name: "SwiftGen", package: "SwiftGen"),
                                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                            ]
                        ),
                        .target(
                            name: "XcbeautifyLib",
                            dependencies: [
                                .product(name: "Colorizer", package: "Colorizer"),
                                .product(name: "XMLCoder", package: "XMLCoder"),
                            ]
                        ),
                    ]
                )
                """}
    end
  end

  describe "package_object_key/2" do
    test "returns the object key for the package" do
      # When
      got = Packages.package_object_key(%{scope: "My", name: "Package"})

      # Then
      assert got == "registry/swift/my/package"
    end

    test "returns the object key for the package with version" do
      # When
      got = Packages.package_object_key(%{scope: "My", name: "Package"}, version: "5.10.1")

      # Then
      assert got == "registry/swift/my/package/5.10.1"
    end

    test "returns the object key for the package with path" do
      # When
      got = Packages.package_object_key(%{scope: "My", name: "Package"}, path: "Package.swift")

      # Then
      assert got == "registry/swift/my/package/Package.swift"
    end

    test "returns the object key for the package with version and path" do
      # When
      got =
        Packages.package_object_key(%{scope: "My", name: "Package"},
          version: "5.10.1",
          path: "Package.swift"
        )

      # Then
      assert got == "registry/swift/my/package/5.10.1/Package.swift"
    end
  end

  describe "create_package_download_event/1" do
    test "creates a package download event" do
      # Given
      package_release = PackagesFixtures.package_release_fixture()
      account = AccountsFixtures.user_fixture(preload: [:account]).account

      # When
      package_download_event =
        Packages.create_package_download_event(%{
          package_release: package_release,
          account: account
        })

      # Then
      assert package_download_event.package_release_id == package_release.id
      assert package_download_event.account_id == account.id
    end
  end
end
