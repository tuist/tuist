defmodule Tuist.Registry.Swift.Workers.CreatePackageReleaseWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  import Ecto.Query
  import ExUnit.CaptureLog, only: [with_log: 1]

  alias Tuist.Registry.Swift.Packages
  alias Tuist.Registry.Swift.Packages.PackageRelease
  alias Tuist.Registry.Swift.Workers.CreatePackageReleaseWorker
  alias Tuist.Repo
  alias Tuist.Storage
  alias Tuist.VCS
  alias Tuist.VCS.Repositories.Content
  alias TuistTestSupport.Fixtures.Registry.Swift.PackagesFixtures

  defp setup_standard_stubs(_scope, _name, version, directory_name) do
    directory_path = "/tmp/briefly--123-test/briefly-456-test/#{directory_name}"
    package_swift_path = "#{directory_path}/Package.swift"

    stub(Storage, :put_object, fn _object_key, _content, _actor -> :ok end)

    stub(VCS, :get_source_archive_by_tag_and_repository_full_handle, fn _ ->
      {:ok, "/tmp/source_archive.zip"}
    end)

    # Default stub for .gitmodules check - indicates no submodules
    stub(VCS, :get_repository_content, fn
      _, [reference: ^version, path: ".gitmodules"] ->
        {:error, :not_found}

      _, _ ->
        {:error, :not_found}
    end)

    stub(Briefly, :create, fn [type: :directory] ->
      {:ok, "/tmp/briefly--123-test/briefly-456-test"}
    end)

    stub(System, :cmd, fn cmd, args ->
      case {cmd, args} do
        {"unzip", ["/tmp/source_archive.zip", "-d", "/tmp/briefly--123-test/briefly-456-test"]} ->
          {"", 0}

        _ ->
          {"", 0}
      end
    end)

    stub(System, :cmd, fn cmd, args, opts ->
      case {cmd, args, opts} do
        {"zip", ["--symlinks", "-r", "/tmp/briefly--123-test/briefly-456-test/source_archive.zip", ^directory_name],
         [cd: "/tmp/briefly--123-test/briefly-456-test"]} ->
          {"", 0}

        _ ->
          {"", 0}
      end
    end)

    stub(File, :ls!, fn path ->
      case path do
        "/tmp/briefly--123-test/briefly-456-test" -> [directory_name]
        ^directory_path -> ["Package.swift"]
        _ -> []
      end
    end)

    stub(File, :read!, fn path ->
      case path do
        ^package_swift_path -> "// swift-tools-version:5.9\ncontent"
        "/tmp/briefly--123-test/briefly-456-test/source_archive.zip" -> "zip_content"
        _ -> "// swift-tools-version:5.9\ncontent"
      end
    end)

    stub(File, :write!, fn _, _ -> :ok end)
    stub(File, :dir?, fn _ -> false end)
  end

  describe "perform/1" do
    test "creates a package release for the given scope, name and version" do
      # Given
      package =
        PackagesFixtures.package_fixture(
          scope: "Alamofire",
          name: "Alamofire"
        )

      setup_standard_stubs("alamofire", "alamofire", "5.10.2", "Alamofire")

      stub(VCS, :get_repository_content, fn
        _, [reference: "5.10.2", path: ".gitmodules"] ->
          {:error, :not_found}

        _, [reference: "5.10.2", path: "Package.swift"] ->
          {:ok, %Content{content: "// swift-tools-version:5.9\ncontent", path: "Package.swift"}}

        _, [reference: "5.10.2"] ->
          {:ok, [%Content{content: nil, path: "Package.swift"}]}
      end)

      job = %Oban.Job{
        args: %{
          "scope" => "Alamofire",
          "name" => "Alamofire",
          "version" => "5.10.2"
        }
      }

      # When
      result = CreatePackageReleaseWorker.perform(job)

      # Then
      assert result == :ok

      package_release = Packages.get_package_release_by_version(%{package: package, version: "5.10.2"})
      assert package_release
      assert package_release.version == "5.10.2"
    end

    test "returns error when package does not exist" do
      # Given
      job = %Oban.Job{
        args: %{
          "scope" => "NonExistent",
          "name" => "Package",
          "version" => "1.0.0"
        }
      }

      # When
      {result, log} =
        with_log(fn ->
          CreatePackageReleaseWorker.perform(job)
        end)

      # Then
      assert result == {:error, :package_not_found}
      assert log =~ "Package NonExistent/Package not found"
    end

    test "handles errors during package release creation" do
      # Given
      PackagesFixtures.package_fixture(
        scope: "ErrorPackage",
        name: "ErrorPackage"
      )

      stub(VCS, :get_source_archive_by_tag_and_repository_full_handle, fn _ ->
        {:error, "API error"}
      end)

      job = %Oban.Job{
        args: %{
          "scope" => "ErrorPackage",
          "name" => "ErrorPackage",
          "version" => "1.0.0"
        }
      }

      # When
      {result, log} =
        with_log(fn ->
          CreatePackageReleaseWorker.perform(job)
        end)

      # Then
      assert match?({:error, _}, result)
      assert log =~ "Failed to create package release for ErrorPackage/ErrorPackage@1.0.0"
    end

    test "creates package release with pre-release version" do
      # Given
      package =
        PackagesFixtures.package_fixture(
          scope: "Alamofire",
          name: "Alamofire"
        )

      setup_standard_stubs("alamofire", "alamofire", "5.10.2-beta", "Alamofire")

      stub(VCS, :get_repository_content, fn
        _, [reference: "5.10.2-beta", path: ".gitmodules"] ->
          {:error, :not_found}

        _, [reference: "5.10.2-beta", path: "Package.swift"] ->
          {:ok, %Content{content: "content", path: "Package.swift"}}

        _, [reference: "5.10.2-beta"] ->
          {:ok, [%Content{content: nil, path: "Package.swift"}]}
      end)

      job = %Oban.Job{
        args: %{
          "scope" => "Alamofire",
          "name" => "Alamofire",
          "version" => "5.10.2-beta"
        }
      }

      # When
      result = CreatePackageReleaseWorker.perform(job)

      # Then
      assert result == :ok

      package_release = Packages.get_package_release_by_version(%{package: package, version: "5.10.2-beta"})
      assert package_release
      assert package_release.version == "5.10.2-beta"
    end

    test "creates package release with v-prefixed version" do
      # Given
      package =
        PackagesFixtures.package_fixture(
          scope: "Alamofire",
          name: "Alamofire"
        )

      setup_standard_stubs("alamofire", "alamofire", "v5.10.2", "Alamofire")

      stub(VCS, :get_repository_content, fn
        _, [reference: "v5.10.2", path: ".gitmodules"] ->
          {:error, :not_found}

        _, [reference: "v5.10.2", path: "Package.swift"] ->
          {:ok, %Content{content: "// swift-tools-version:5.9\ncontent", path: "Package.swift"}}

        _, [reference: "v5.10.2"] ->
          {:ok, [%Content{content: nil, path: "Package.swift"}]}
      end)

      job = %Oban.Job{
        args: %{
          "scope" => "Alamofire",
          "name" => "Alamofire",
          "version" => "v5.10.2"
        }
      }

      # When
      result = CreatePackageReleaseWorker.perform(job)

      # Then
      assert result == :ok

      # Note: semantic_version strips "v" prefix, so we look for "5.10.2"
      package_release = Packages.get_package_release_by_version(%{package: package, version: "5.10.2"})
      assert package_release
      assert package_release.version == "5.10.2"
    end

    test "creates package release with multiple Package.swift manifests for different Swift versions" do
      # Given
      package =
        PackagesFixtures.package_fixture(
          scope: "Alamofire",
          name: "Alamofire"
        )

      setup_standard_stubs("alamofire", "alamofire", "5.10.2", "Alamofire")

      stub(File, :ls!, fn
        "/tmp/briefly--123-test/briefly-456-test" ->
          ["Alamofire"]

        "/tmp/briefly--123-test/briefly-456-test/Alamofire" ->
          [
            "Package.swift",
            "Package@swift-5.9.swift",
            "Package@swift-5.8.swift",
            "Package@swift-5.7.swift"
          ]
      end)

      stub(VCS, :get_repository_content, fn
        _, [reference: "5.10.2", path: ".gitmodules"] ->
          {:error, :not_found}

        _, [reference: "5.10.2", path: "Package.swift"] ->
          {:ok, %Content{content: "content", path: "Package.swift"}}

        _, [reference: "5.10.2", path: "Package@swift-5.9.swift"] ->
          {:ok, %Content{content: "// swift-tools-version:5.9\ncontent", path: "Package@swift-5.9.swift"}}

        _, [reference: "5.10.2", path: "Package@swift-5.8.swift"] ->
          {:ok, %Content{content: "// swift-tools-version:5.8\ncontent", path: "Package@swift-5.8.swift"}}

        _, [reference: "5.10.2", path: "Package@swift-5.7.swift"] ->
          {:ok, %Content{content: "// swift-tools-version:5.7\ncontent", path: "Package@swift-5.7.swift"}}

        _, [reference: "5.10.2"] ->
          {:ok,
           [
             %Content{content: nil, path: "Package.swift"},
             %Content{content: nil, path: "Package@swift-5.9.swift"},
             %Content{content: nil, path: "Package@swift-5.8.swift"},
             %Content{content: nil, path: "Package@swift-5.7.swift"}
           ]}
      end)

      job = %Oban.Job{
        args: %{
          "scope" => "Alamofire",
          "name" => "Alamofire",
          "version" => "5.10.2"
        }
      }

      # When
      result = CreatePackageReleaseWorker.perform(job)

      # Then
      assert result == :ok

      package_release =
        %{package: package, version: "5.10.2"}
        |> Packages.get_package_release_by_version()
        |> Repo.preload(:manifests)

      assert package_release
      assert package_release.version == "5.10.2"
      assert Enum.count(package_release.manifests) == 4

      swift_versions = package_release.manifests |> Enum.map(& &1.swift_tools_version) |> Enum.sort()
      assert swift_versions == [nil, "5.7", "5.8", "5.9"]
    end

    test "creates package release when Package.swift includes binary references" do
      # Given
      package =
        PackagesFixtures.package_fixture(
          scope: "TestPackage",
          name: "TestPackage"
        )

      package_swift_content = """
      // swift-tools-version:5.9
      import PackageDescription

      let package = Package(
          name: "TestPackage",
          products: [
              .library(name: "TestPackage", targets: ["TestPackage"]),
          ],
          targets: [
              .binaryTarget(
                  name: "TestPackage",
                  url: "https://github.com/example/binary.zip",
                  checksum: "abc123"
              )
          ]
      )
      """

      setup_standard_stubs("testpackage", "testpackage", "1.0.0", "TestPackage")

      stub(File, :read!, fn
        "/tmp/briefly--123-test/briefly-456-test/TestPackage/Package.swift" -> package_swift_content
        "/tmp/briefly--123-test/briefly-456-test/source_archive.zip" -> "zip_content"
      end)

      stub(VCS, :get_repository_content, fn
        _, [reference: "1.0.0", path: ".gitmodules"] ->
          {:error, :not_found}

        _, [reference: "1.0.0", path: "Package.swift"] ->
          {:ok, %Content{content: package_swift_content, path: "Package.swift"}}

        _, [reference: "1.0.0"] ->
          {:ok, [%Content{content: nil, path: "Package.swift"}]}
      end)

      job = %Oban.Job{
        args: %{
          "scope" => "TestPackage",
          "name" => "TestPackage",
          "version" => "1.0.0"
        }
      }

      # When
      result = CreatePackageReleaseWorker.perform(job)

      # Then
      assert result == :ok

      package_release = Packages.get_package_release_by_version(%{package: package, version: "1.0.0"})
      assert package_release
      assert package_release.version == "1.0.0"
    end

    test "skips Package.swift upload when none exists in repository" do
      # Given
      package =
        PackagesFixtures.package_fixture(
          scope: "NoPackage",
          name: "NoPackage"
        )

      setup_standard_stubs("nopackage", "nopackage", "1.0.0", "NoPackage")

      stub(File, :ls!, fn
        "/tmp/briefly--123-test/briefly-456-test" -> ["NoPackage"]
        "/tmp/briefly--123-test/briefly-456-test/NoPackage" -> []
      end)

      stub(VCS, :get_repository_content, fn
        _, [reference: "1.0.0", path: ".gitmodules"] ->
          {:error, :not_found}

        _, [reference: "1.0.0"] ->
          {:ok, []}
      end)

      job = %Oban.Job{
        args: %{
          "scope" => "NoPackage",
          "name" => "NoPackage",
          "version" => "1.0.0"
        }
      }

      # When
      result = CreatePackageReleaseWorker.perform(job)

      # Then
      assert result == :ok

      package_release =
        %{package: package, version: "1.0.0"}
        |> Packages.get_package_release_by_version()
        |> Repo.preload(:manifests)

      assert package_release
      assert package_release.version == "1.0.0"
      assert Enum.count(package_release.manifests) == 0
    end

    test "handles Package.swift with String interpolation in package URLs" do
      # Given
      package =
        PackagesFixtures.package_fixture(
          scope: "TestPackage",
          name: "TestPackage"
        )

      package_swift_content = """
      // swift-tools-version: 6.0
      import PackageDescription

      let package = Package(
        name: "TestPackage",
        dependencies: [
          .package(url: "https://github.com/\\(organization)/\\(packageName).git", from: "1.0.0"),
          Dependency.swift(repositoryName: "docc-plugin").package
        ]
      )
      """

      setup_standard_stubs("testpackage", "testpackage", "1.0.0", "TestPackage")

      stub(File, :read!, fn
        "/tmp/briefly--123-test/briefly-456-test/TestPackage/Package.swift" -> package_swift_content
        "/tmp/briefly--123-test/briefly-456-test/source_archive.zip" -> "zip_content"
      end)

      stub(VCS, :get_repository_content, fn
        _, [reference: "1.0.0", path: ".gitmodules"] ->
          {:error, :not_found}

        _, [reference: "1.0.0", path: "Package.swift"] ->
          {:ok, %Content{content: package_swift_content, path: "Package.swift"}}

        _, [reference: "1.0.0"] ->
          {:ok, [%Content{content: nil, path: "Package.swift"}]}
      end)

      job = %Oban.Job{
        args: %{
          "scope" => "TestPackage",
          "name" => "TestPackage",
          "version" => "1.0.0"
        }
      }

      # When
      result = CreatePackageReleaseWorker.perform(job)

      # Then
      assert result == :ok

      package_release = Packages.get_package_release_by_version(%{package: package, version: "1.0.0"})
      assert package_release
      assert package_release.version == "1.0.0"
    end

    test "handles Package.swift with header search paths" do
      # Given
      package =
        PackagesFixtures.package_fixture(
          scope: "TestPackage",
          name: "TestPackage"
        )

      package_swift_content = """
      // swift-tools-version:5.9
      import PackageDescription

      let package = Package(
          name: "TestPackage",
          dependencies: [
              .package(url: "https://github.com/example/Dependency.git", from: "3.0.2"),
          ],
          targets: [
              .target(
                  name: "TestPackage",
                  dependencies: ["Dependency"],
                  path: "Source/Classes",
                  publicHeadersPath: "include",
                  cSettings: [
                      .headerSearchPath("Dependency"),
                      .headerSearchPath("../External/Headers")
                  ]
              ),
          ]
      )
      """

      expected_manifest_content = """
      // swift-tools-version:5.9
      import PackageDescription

      let package = Package(
          name: "TestPackage",
          dependencies: [
              .package(url: "https://github.com/example/Dependency.git", from: "3.0.2"),
          ],
          targets: [
              .target(
                  name: "TestPackage",
                  dependencies: [.product(name: "Dependency", package: "Dependency")],
                  path: "Source/Classes",
                  publicHeadersPath: "include",
                  cSettings: [
                      .headerSearchPath("Dependency"),
                      .headerSearchPath("../External/Headers")
                  ]
              ),
          ]
      )
      """

      setup_standard_stubs("testpackage", "testpackage", "1.0.0", "TestPackage")

      stub(File, :read!, fn
        "/tmp/briefly--123-test/briefly-456-test/TestPackage/Package.swift" -> package_swift_content
        "/tmp/briefly--123-test/briefly-456-test/source_archive.zip" -> "zip_content"
      end)

      stub(File, :write!, fn
        "/tmp/briefly--123-test/briefly-456-test/TestPackage/Package.swift", content ->
          # Verify the manifest was transformed correctly
          assert content == expected_manifest_content
          :ok

        _, _ ->
          :ok
      end)

      stub(VCS, :get_repository_content, fn
        _, [reference: "1.0.0", path: ".gitmodules"] ->
          {:error, :not_found}

        _, [reference: "1.0.0", path: "Package.swift"] ->
          {:ok, %Content{content: package_swift_content, path: "Package.swift"}}

        _, [reference: "1.0.0"] ->
          {:ok, [%Content{content: nil, path: "Package.swift"}]}
      end)

      job = %Oban.Job{
        args: %{
          "scope" => "TestPackage",
          "name" => "TestPackage",
          "version" => "1.0.0"
        }
      }

      # When
      result = CreatePackageReleaseWorker.perform(job)

      # Then
      assert result == :ok

      package_release = Packages.get_package_release_by_version(%{package: package, version: "1.0.0"})
      assert package_release
      assert package_release.version == "1.0.0"
    end

    test "handles Package.swift with .byName product references" do
      # Given
      package =
        PackagesFixtures.package_fixture(
          scope: "TestPackage",
          name: "TestPackage"
        )

      package_swift_content = """
      // swift-tools-version:5.9
      import PackageDescription

      let package = Package(
          name: "TestPackage",
          dependencies: [
              .package(url: "https://github.com/example/FirstDependency.git", from: "3.0.2"),
              .package(name: "CustomName", url: "https://github.com/example/SecondDependency.git", from: "1.0.0"),
          ],
          targets: [
              .target(
                  name: "TestPackage",
                  dependencies: [
                    .byName(name: "FirstDependency"),
                    .byName(name: "CustomName")
                  ]
              ),
          ]
      )
      """

      expected_manifest_content = """
      // swift-tools-version:5.9
      import PackageDescription

      let package = Package(
          name: "TestPackage",
          dependencies: [
              .package(url: "https://github.com/example/FirstDependency.git", from: "3.0.2"),
              .package(name: "SecondDependency", url: "https://github.com/example/SecondDependency.git", from: "1.0.0"),
          ],
          targets: [
              .target(
                  name: "TestPackage",
                  dependencies: [
                    .product(name: "FirstDependency", package: "FirstDependency"),
                    .product(name: "SecondDependency", package: "SecondDependency")
                  ]
              ),
          ]
      )
      """

      setup_standard_stubs("testpackage", "testpackage", "1.0.0", "TestPackage")

      stub(File, :read!, fn
        "/tmp/briefly--123-test/briefly-456-test/TestPackage/Package.swift" -> package_swift_content
        "/tmp/briefly--123-test/briefly-456-test/source_archive.zip" -> "zip_content"
      end)

      stub(File, :write!, fn
        "/tmp/briefly--123-test/briefly-456-test/TestPackage/Package.swift", content ->
          # Verify the .byName references were replaced correctly
          assert content == expected_manifest_content
          :ok

        _, _ ->
          :ok
      end)

      stub(VCS, :get_repository_content, fn
        _, [reference: "1.0.0", path: ".gitmodules"] ->
          {:error, :not_found}

        _, [reference: "1.0.0", path: "Package.swift"] ->
          {:ok, %Content{content: package_swift_content, path: "Package.swift"}}

        _, [reference: "1.0.0"] ->
          {:ok, [%Content{content: nil, path: "Package.swift"}]}
      end)

      job = %Oban.Job{
        args: %{
          "scope" => "TestPackage",
          "name" => "TestPackage",
          "version" => "1.0.0"
        }
      }

      # When
      result = CreatePackageReleaseWorker.perform(job)

      # Then
      assert result == :ok

      package_release = Packages.get_package_release_by_version(%{package: package, version: "1.0.0"})
      assert package_release
      assert package_release.version == "1.0.0"
    end

    test "verifies manifest fixing logic transforms package references correctly" do
      # Given
      package =
        PackagesFixtures.package_fixture(
          scope: "TestPackage",
          name: "TestPackage"
        )

      # Complex manifest with multiple edge cases
      package_swift_content = """
      // swift-tools-version:5.9
      import PackageDescription

      let package = Package(
          name: "TestPackage",
          products: [
              .library(name: "TestPackage", targets: ["TestPackage"]),
          ],
          dependencies: [
              .package(url: "https://github.com/alamofire/Alamofire.git", from: "5.0.0"),
              .package(name: "CustomCache", url: "https://github.com/pinterest/PINCache.git", from: "3.0.2"),
              .package(url: "https://github.com/realm/SwiftLint.git", from: "0.50.0"),
          ],
          targets: [
              .target(
                  name: "TestPackage",
                  dependencies: [
                    "Alamofire",
                    .byName(name: "CustomCache"),
                    "SwiftLint"
                  ]
              ),
              .testTarget(
                  name: "TestPackageTests",
                  dependencies: ["TestPackage", "Alamofire"]
              )
          ]
      )
      """

      expected_manifest_content = """
      // swift-tools-version:5.9
      import PackageDescription

      let package = Package(
          name: "TestPackage",
          products: [
              .library(name: "TestPackage", targets: ["TestPackage"]),
          ],
          dependencies: [
              .package(url: "https://github.com/alamofire/Alamofire.git", from: "5.0.0"),
              .package(name: "PINCache", url: "https://github.com/pinterest/PINCache.git", from: "3.0.2"),
              .package(url: "https://github.com/realm/SwiftLint.git", from: "0.50.0"),
          ],
          targets: [
              .target(
                  name: "TestPackage",
                  dependencies: [
                    .product(name: "Alamofire", package: "Alamofire"),
                    .product(name: "PINCache", package: "PINCache"),
                    .product(name: "SwiftLint", package: "SwiftLint")
                  ]
              ),
              .testTarget(
                  name: "TestPackageTests",
                  dependencies: ["TestPackage", .product(name: "Alamofire", package: "Alamofire")]
              )
          ]
      )
      """

      setup_standard_stubs("testpackage", "testpackage", "1.0.0", "TestPackage")

      stub(File, :read!, fn
        "/tmp/briefly--123-test/briefly-456-test/TestPackage/Package.swift" -> package_swift_content
        "/tmp/briefly--123-test/briefly-456-test/source_archive.zip" -> "zip_content"
      end)

      stub(File, :write!, fn
        "/tmp/briefly--123-test/briefly-456-test/TestPackage/Package.swift", content ->
          # Verify all transformations were applied correctly
          assert content == expected_manifest_content
          :ok

        _, _ ->
          :ok
      end)

      stub(VCS, :get_repository_content, fn
        _, [reference: "1.0.0", path: ".gitmodules"] ->
          {:error, :not_found}

        _, [reference: "1.0.0", path: "Package.swift"] ->
          {:ok, %Content{content: package_swift_content, path: "Package.swift"}}

        _, [reference: "1.0.0"] ->
          {:ok, [%Content{content: nil, path: "Package.swift"}]}
      end)

      job = %Oban.Job{
        args: %{
          "scope" => "TestPackage",
          "name" => "TestPackage",
          "version" => "1.0.0"
        }
      }

      # When
      result = CreatePackageReleaseWorker.perform(job)

      # Then
      assert result == :ok

      package_release = Packages.get_package_release_by_version(%{package: package, version: "1.0.0"})
      assert package_release
      assert package_release.version == "1.0.0"
    end

    test "perform/1 skips creation when package release already exists" do
      # Given
      package = PackagesFixtures.package_fixture()

      existing_package_release =
        PackagesFixtures.package_release_fixture(
          package_id: package.id,
          version: "1.0.0",
          checksum: "existing_checksum"
        )

      setup_standard_stubs("TestPackage", "TestPackage", "1.0.0", "TestPackage-1.0.0")

      job = %Oban.Job{
        args: %{
          "scope" => package.scope,
          "name" => package.name,
          "version" => "1.0.0"
        }
      }

      # When
      result = CreatePackageReleaseWorker.perform(job)

      # Then
      assert result == :ok

      package_release = Packages.get_package_release_by_version(%{package: package, version: "1.0.0"})
      assert package_release.id == existing_package_release.id
      assert package_release.checksum == "existing_checksum"

      all_releases = Repo.all(from pr in PackageRelease, where: pr.package_id == ^package.id and pr.version == "1.0.0")
      assert length(all_releases) == 1
    end

    test "perform/1 skips creation when package release already exists with version normalization" do
      # Given
      package = PackagesFixtures.package_fixture()

      existing_package_release =
        PackagesFixtures.package_release_fixture(
          package_id: package.id,
          version: "1.0.0",
          checksum: "existing_checksum"
        )

      setup_standard_stubs("TestPackage", "TestPackage", "1.0", "TestPackage-1.0")

      job = %Oban.Job{
        args: %{
          "scope" => package.scope,
          "name" => package.name,
          # This will be normalized to "1.0.0"
          "version" => "1.0"
        }
      }

      # When
      result = CreatePackageReleaseWorker.perform(job)

      # Then
      assert result == :ok

      package_release = Packages.get_package_release_by_version(%{package: package, version: "1.0.0"})
      assert package_release.id == existing_package_release.id
      assert package_release.checksum == "existing_checksum"
      all_releases = Repo.all(from pr in PackageRelease, where: pr.package_id == ^package.id and pr.version == "1.0.0")
      assert length(all_releases) == 1
    end
  end
end
