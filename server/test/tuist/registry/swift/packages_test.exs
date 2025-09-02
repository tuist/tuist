defmodule Tuist.Registry.Swift.PackagesTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Base64
  alias Tuist.Registry.Swift.Packages
  alias Tuist.Repo
  alias Tuist.Storage
  alias Tuist.VCS
  alias Tuist.VCS.Repositories.Content
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

  describe "create_missing_package_releases/1" do
    test "creates missing package releases" do
      # Given
      package =
        PackagesFixtures.package_fixture(
          scope: "Alamofire",
          name: "Alamofire"
        )

      PackagesFixtures.package_release_fixture(package_id: package.id, version: "5.10.1")

      stub(Storage, :put_object, fn
        "registry/swift/alamofire/alamofire/5.10.2/Package.swift", _ -> :ok
        "registry/swift/alamofire/alamofire/5.10.2/source_archive.zip", _ -> :ok
        "registry/swift/alamofire/alamofire/5.10.0/Package.swift", _ -> :ok
        "registry/swift/alamofire/alamofire/5.10.0/source_archive.zip", _ -> :ok
        "registry/swift/alamofire/alamofire/5.11.0/Package.swift", _ -> :ok
        "registry/swift/alamofire/alamofire/5.11.0/source_archive.zip", _ -> :ok
      end)

      stub(VCS, :get_tags, fn _ ->
        [
          %Tag{name: "5.10.2"},
          %Tag{name: "5.10.1"},
          %Tag{name: "5.10.0"},
          %Tag{name: "5.11"},
          %Tag{name: "tag@5.0.0"}
        ]
      end)

      stub(VCS, :get_source_archive_by_tag_and_repository_full_handle, fn _ ->
        {:ok, "/tmp/source_archive.zip"}
      end)

      stub(System, :cmd, fn _, _ -> {"", 0} end)
      stub(System, :cmd, fn _, _, _ -> {"", 0} end)
      stub(File, :ls!, fn _ -> ["Alamofire"] end)

      stub(File, :read!, fn _ ->
        "content"
      end)

      stub(VCS, :get_repository_content, fn
        _, [reference: _, path: "Package.swift"] ->
          {:ok, %Content{content: "content", path: "Package.swift"}}

        _, _ ->
          {:ok, [%Content{path: "Package.swift"}]}
      end)

      stub(Base64, :decode, fn "content" -> "content" end)

      # When
      got =
        Packages.create_missing_package_releases(%{
          package: Repo.preload(package, :package_releases),
          token: "github_token"
        })

      # Then
      assert Enum.map(got, & &1.version) == [
               "5.10.2",
               "5.10.0",
               "5.11.0"
             ]

      assert got
             |> Repo.preload(:manifests)
             |> Enum.map(&Enum.count(&1.manifests)) == [
               1,
               1,
               1
             ]
    end

    test "skips package release with a v prefix when its semantic variant has already been created" do
      # Given
      package =
        PackagesFixtures.package_fixture(
          scope: "Alamofire",
          name: "Alamofire"
        )

      PackagesFixtures.package_release_fixture(package_id: package.id, version: "5.10.2")

      stub(VCS, :get_tags, fn _ ->
        [
          %Tag{name: "v5.10.2"}
        ]
      end)

      # When
      got =
        Packages.create_missing_package_releases(%{
          package: Repo.preload(package, :package_releases),
          token: "github_token"
        })

      # Then
      assert got == []
    end

    test "creates only a single package release when both semantic and non-semantic tag for the same version exist" do
      # Given
      package =
        PackagesFixtures.package_fixture(
          scope: "Alamofire",
          name: "Alamofire",
          preload: [:package_releases]
        )

      stub(Storage, :put_object, fn
        "registry/swift/alamofire/alamofire/5.10.2/Package.swift", _ -> :ok
        "registry/swift/alamofire/alamofire/5.10.2/source_archive.zip", _ -> :ok
      end)

      stub(VCS, :get_tags, fn _ ->
        [
          %Tag{name: "v5.10.2"},
          %Tag{name: "5.10.2"}
        ]
      end)

      stub(VCS, :get_source_archive_by_tag_and_repository_full_handle, fn _ ->
        {:ok, "/tmp/source_archive.zip"}
      end)

      stub(System, :cmd, fn _, _ -> {"", 0} end)
      stub(System, :cmd, fn _, _, _ -> {"", 0} end)

      stub(File, :ls!, fn _ ->
        ["Alamofire"]
      end)

      stub(File, :read!, fn _ ->
        "content"
      end)

      stub(VCS, :get_repository_content, fn _, _ ->
        {:ok, [%Content{path: "File.swift", content: "content"}]}
      end)

      stub(Base64, :decode, fn "content" -> "content" end)

      # When
      got = Packages.create_missing_package_releases(%{package: package, token: "github_token"})

      # Then
      assert Enum.map(got, & &1.version) == [
               "5.10.2"
             ]
    end

    test "creates missing package releases where versions are in the format of vX.Y.Z" do
      # Given
      package =
        PackagesFixtures.package_fixture(
          scope: "Alamofire",
          name: "Alamofire",
          preload: [:package_releases]
        )

      stub(Storage, :put_object, fn
        "registry/swift/alamofire/alamofire/5.10.2/Package.swift", _ -> :ok
        "registry/swift/alamofire/alamofire/5.10.2/source_archive.zip", _ -> :ok
      end)

      stub(VCS, :get_tags, fn _ ->
        [
          %Tag{name: "v5.10.2"}
        ]
      end)

      stub(VCS, :get_source_archive_by_tag_and_repository_full_handle, fn _ ->
        {:ok, "/tmp/source_archive.zip"}
      end)

      stub(System, :cmd, fn _, _ -> {"", 0} end)
      stub(System, :cmd, fn _, _, _ -> {"", 0} end)

      stub(File, :ls!, fn _ ->
        ["Alamofire"]
      end)

      stub(File, :read!, fn _ ->
        "content"
      end)

      stub(VCS, :get_repository_content, fn _, _ ->
        {:ok, [%Content{path: "File.swift", content: "content"}]}
      end)

      stub(Base64, :decode, fn "content" -> "content" end)

      # When
      got = Packages.create_missing_package_releases(%{package: package, token: "github_token"})

      # Then
      assert Enum.map(got, & &1.version) == [
               "5.10.2"
             ]
    end

    test "creates missing package pre-releases" do
      # Given
      package =
        PackagesFixtures.package_fixture(
          scope: "Alamofire",
          name: "Alamofire",
          preload: [:package_releases]
        )

      stub(Storage, :put_object, fn
        "registry/swift/alamofire/alamofire/5.10.2-beta/Package.swift", _ -> :ok
        "registry/swift/alamofire/alamofire/5.10.2-beta/source_archive.zip", _ -> :ok
        "registry/swift/alamofire/alamofire/5.10.2-beta+1/Package.swift", _ -> :ok
        "registry/swift/alamofire/alamofire/5.10.2-beta+1/source_archive.zip", _ -> :ok
        "registry/swift/alamofire/alamofire/5.10.2-beta+2/Package.swift", _ -> :ok
        "registry/swift/alamofire/alamofire/5.10.2-beta+2/source_archive.zip", _ -> :ok
        "registry/swift/alamofire/alamofire/5.10.2-beta-3/Package.swift", _ -> :ok
        "registry/swift/alamofire/alamofire/5.10.2-beta-3/source_archive.zip", _ -> :ok
      end)

      stub(VCS, :get_tags, fn _ ->
        [
          %Tag{name: "5.10.2-beta"},
          %Tag{name: "5.10.2-beta.1"},
          %Tag{name: "v5.10.2-beta.2"},
          %Tag{name: "5.10.2-beta-3"}
        ]
      end)

      stub(VCS, :get_source_archive_by_tag_and_repository_full_handle, fn _ ->
        {:ok, [{~c"File.swift", "File contents"}]}
      end)

      stub(VCS, :get_source_archive_by_tag_and_repository_full_handle, fn _ ->
        {:ok, "/tmp/source_archive.zip"}
      end)

      stub(System, :cmd, fn _, _ -> {"", 0} end)
      stub(System, :cmd, fn _, _, _ -> {"", 0} end)

      stub(File, :ls!, fn _ ->
        ["Alamofire"]
      end)

      stub(File, :read!, fn _ ->
        "content"
      end)

      stub(VCS, :get_repository_content, fn _, _ ->
        {:ok, [%Content{path: "File.swift", content: "content"}]}
      end)

      stub(Base64, :decode, fn "content" -> "content" end)

      # When
      got = Packages.create_missing_package_releases(%{package: package, token: "github_token"})

      # Then
      assert Enum.map(got, & &1.version) == [
               "5.10.2-beta",
               "5.10.2-beta+1",
               "5.10.2-beta+2",
               "5.10.2-beta-3"
             ]
    end

    test "skips dev versions like 0.9.3-dev1985" do
      # Given
      package =
        PackagesFixtures.package_fixture(
          scope: "TestScope",
          name: "TestPackage",
          preload: [:package_releases]
        )

      stub(Storage, :put_object, fn
        "registry/swift/testscope/testpackage/1.0.0/Package.swift", _ -> :ok
        "registry/swift/testscope/testpackage/1.0.0/source_archive.zip", _ -> :ok
        "registry/swift/testscope/testpackage/2.0.0-alpha/Package.swift", _ -> :ok
        "registry/swift/testscope/testpackage/2.0.0-alpha/source_archive.zip", _ -> :ok
      end)

      stub(VCS, :get_tags, fn _ ->
        [
          %Tag{name: "1.0.0"},
          %Tag{name: "0.9.3-dev1985"},
          %Tag{name: "1.2.3-dev"},
          %Tag{name: "2.0.0-dev456"},
          %Tag{name: "2.0.0-alpha"}
        ]
      end)

      stub(VCS, :get_source_archive_by_tag_and_repository_full_handle, fn _ ->
        {:ok, "/tmp/source_archive.zip"}
      end)

      stub(System, :cmd, fn _, _ -> {"", 0} end)
      stub(System, :cmd, fn _, _, _ -> {"", 0} end)

      stub(File, :ls!, fn _ ->
        ["TestPackage"]
      end)

      stub(File, :read!, fn _ ->
        "content"
      end)

      stub(VCS, :get_repository_content, fn _, _ ->
        {:ok, [%Content{path: "File.swift", content: "content"}]}
      end)

      stub(Base64, :decode, fn "content" -> "content" end)

      # When
      got = Packages.create_missing_package_releases(%{package: package, token: "github_token"})

      # Then
      # Should only include 1.0.0 and 2.0.0-alpha, excluding all dev versions
      assert Enum.map(got, & &1.version) == [
               "1.0.0",
               "2.0.0-alpha"
             ]
    end

    test "creates missing package releases Package.swift includes references to binaries" do
      # Given
      package =
        PackagesFixtures.package_fixture(
          scope: "imgly",
          name: "vesdk-ios-build",
          preload: [:package_releases]
        )

      stub(Storage, :put_object, fn
        "registry/swift/imgly/vesdk-ios-build/5.10.2/Package.swift", _ -> :ok
        "registry/swift/imgly/vesdk-ios-build/5.10.2/source_archive.zip", _ -> :ok
      end)

      stub(VCS, :get_tags, fn _ ->
        [
          %Tag{name: "5.10.2"}
        ]
      end)

      package_manifest_content = """
      // swift-tools-version:5.3
      import PackageDescription

      let package = Package(
        name: "VideoEditorSDK",
        platforms: [.iOS(.v9)],
        products: [
          .library(name: "ImglyKit", targets: ["ImglyKit"]),
          .library(name: "VideoEditorSDK", targets: ["VideoEditorSDK"])
        ],
        targets: [
          .binaryTarget(name: "ImglyKit", url: "https://github.com/imgly/vesdk-ios-build/releases/download/10.19.0/VideoEditorSDK.zip", checksum: "e6bd0d2047bba53096c7f09d6e121fb11a345c97028770a002747bc854cfa8b8"),
          .binaryTarget(name: "VideoEditorSDK", url: "https://github.com/imgly/vesdk-ios-build/releases/download/10.19.0/VideoEditorSDK.zip", checksum: "e6bd0d2047bba53096c7f09d6e121fb11a345c97028770a002747bc854cfa8b8")
        ]
      )
      """

      stub(VCS, :get_source_archive_by_tag_and_repository_full_handle, fn _ ->
        {:ok, "/tmp/source_archive.zip"}
      end)

      stub(System, :cmd, fn _, _ -> {"", 0} end)
      stub(System, :cmd, fn _, _, _ -> {"", 0} end)

      stub(File, :ls!, fn path ->
        if String.ends_with?(path, ".zip") do
          ["VideoEditorSDK"]
        else
          ["Package.swift"]
        end
      end)

      expect(File, :write!, fn path, content ->
        assert String.ends_with?(path, "Package.swift")
        assert content == package_manifest_content
      end)

      stub(File, :read!, fn path ->
        if String.ends_with?(path, "Package.swift") do
          package_manifest_content
        else
          "content"
        end
      end)

      stub(VCS, :get_repository_content, fn _, _ ->
        {:ok, [%Content{path: "File.swift", content: "content"}]}
      end)

      stub(Base64, :decode, fn "content" -> "content" end)

      # When
      got = Packages.create_missing_package_releases(%{package: package, token: "github_token"})

      # Then
      assert Enum.map(got, & &1.version) == [
               "5.10.2"
             ]
    end

    test "creates missing package releases when Package.swift includes url references with String interpolation" do
      # Given

      package =
        PackagesFixtures.package_fixture(
          scope: "catterwaul",
          name: "tuplay",
          preload: [:package_releases]
        )

      stub(Storage, :put_object, fn
        "registry/swift/catterwaul/tuplay/5.10.2/Package.swift", _ -> :ok
        "registry/swift/catterwaul/tuplay/5.10.2/source_archive.zip", _ -> :ok
      end)

      stub(VCS, :get_tags, fn _ ->
        [
          %Tag{name: "5.10.2"}
        ]
      end)

      package_manifest_content = """
      // swift-tools-version: 6.0
      import PackageDescription

      let package = Package(
        name: "Tuplay",
        dependencies: [
          Dependency.swift(repositoryName: "docc-plugin").package
        ]
      )

      struct Dependency {
        let package: Package.Dependency
        let product: Target.Dependency
      }

      extension Dependency {
        static func swift(organization: String = "swiftlang", repositoryName: String) -> Self {
          .init(
            organization: organization,
            name: repositoryName.split(separator: "-").map(\.capitalized).joined(),
            repositoryName: "swift-\(repositoryName)"
          )
        }

        private init(organization: String, name: String, repositoryName: String, branch: String? = nil) {
          self.init(
            package: .package(
              url: "https://github.com/\\(organization)/\\(repositoryName)",
              branch: branch ?? "main"
            ),
            product: .product(name: name, package: repositoryName)
          )
        }
      }
      """

      stub(VCS, :get_source_archive_by_tag_and_repository_full_handle, fn _ ->
        {:ok, "/tmp/source_archive.zip"}
      end)

      stub(System, :cmd, fn _, _ -> {"", 0} end)
      stub(System, :cmd, fn _, _, _ -> {"", 0} end)

      stub(File, :ls!, fn _ ->
        ["Package.swift"]
      end)

      expect(File, :write!, fn path, content ->
        assert String.ends_with?(path, "Package.swift")
        assert content == package_manifest_content
      end)

      stub(File, :read!, fn path ->
        if String.ends_with?(path, "Package.swift") do
          package_manifest_content
        else
          "content"
        end
      end)

      stub(VCS, :get_repository_content, fn _, _ ->
        {:ok, [%Content{path: "File.swift", content: "content"}]}
      end)

      stub(Base64, :decode, fn "content" -> "content" end)

      # When
      got = Packages.create_missing_package_releases(%{package: package, token: "github_token"})

      # Then
      assert Enum.map(got, & &1.version) == [
               "5.10.2"
             ]
    end

    test "creates missing package releases when Package.swift includes package name is referenced outside Package model" do
      # Given
      package =
        PackagesFixtures.package_fixture(
          scope: "firebase",
          name: "firebase-ios-sdk",
          preload: [:package_releases]
        )

      stub(Storage, :put_object, fn
        "registry/swift/firebase/firebase-ios-sdk/5.10.2/Package.swift", _ -> :ok
        "registry/swift/firebase/firebase-ios-sdk/5.10.2/source_archive.zip", _ -> :ok
      end)

      stub(VCS, :get_tags, fn _ ->
        [
          %Tag{name: "5.10.2"}
        ]
      end)

      package_manifest_content = """
      // swift-tools-version: 6.0
      import PackageDescription

      import PackageDescription
      import class Foundation.ProcessInfo

      let firebaseVersion = "10.7.0"

      let package = Package(
        name: "Firebase",
        dependencies: [
          .package(
            name: "GoogleAppMeasurement",
            url: "https://github.com/google/GoogleAppMeasurement.git",
            .exact("10.6.0")
          ),
        ],
        targets: [
          .target(
            name: "FirebaseAnalyticsWrapper",
            dependencies: [
              .target(name: "FirebaseAnalytics", condition: .when(platforms: [.iOS, .macOS, .tvOS])),
              .product(name: "GoogleAppMeasurement", package: "GoogleAppMeasurement"),
            ]
          ),
        ]
      )
      if ProcessInfo.processInfo.environment["FIREBASECI_USE_LATEST_GOOGLEAPPMEASUREMENT"] != nil {
        if let GoogleAppMeasurementIndex = package.dependencies
          .firstIndex(where: { $0.name == "GoogleAppMeasurement" }) {
          package.dependencies[GoogleAppMeasurementIndex] = .package(
            name: "GoogleAppMeasurement",
            url: "https://github.com/google/GoogleAppMeasurement.git",
            .branch("main")
          )
        }
      }
      """

      stub(VCS, :get_source_archive_by_tag_and_repository_full_handle, fn _ ->
        {:ok, "/tmp/source_archive.zip"}
      end)

      stub(System, :cmd, fn _, _ -> {"", 0} end)
      stub(System, :cmd, fn _, _, _ -> {"", 0} end)

      stub(File, :ls!, fn _ ->
        ["Package.swift"]
      end)

      expect(File, :write!, fn path, content ->
        assert String.ends_with?(path, "Package.swift")
        assert content == package_manifest_content
      end)

      stub(File, :read!, fn path ->
        if String.ends_with?(path, "Package.swift") do
          package_manifest_content
        else
          "content"
        end
      end)

      stub(VCS, :get_repository_content, fn _, _ ->
        {:ok, [%Content{path: "File.swift", content: "content"}]}
      end)

      stub(Base64, :decode, fn "content" -> "content" end)

      # When
      got = Packages.create_missing_package_releases(%{package: package, token: "github_token"})

      # Then
      assert Enum.map(got, & &1.version) == [
               "5.10.2"
             ]
    end

    test "creates missing package releases with fixed Package.swift manifests when package products are referenced by name" do
      # Given
      package =
        PackagesFixtures.package_fixture(
          scope: "Alamofire",
          name: "Alamofire",
          preload: [:package_releases]
        )

      stub(VCS, :get_tags, fn _ ->
        [
          %Tag{name: "v5.10.2"}
        ]
      end)

      initial_package_manifest_content = """
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
              .package(
                url: "https://github.com/google/promises.git",
                "2.4.0" ..< "3.0.0"
              ),
              .package(
                name: "OCMock",
                url: "https://github.com/erikdoe/ocmock.git",
                .revision("c5eeaa6dde7c308a5ce48ae4d4530462dd3a1110")
              ),
              .package(name: "libwebp",
                       url: "https://github.com/SDWebImage/libwebp-Xcode",
                       from: "1.1.0"),
              .package(name: "MetricsReporter", url: "https://github.com/rudderlabs/metrics-reporter-ios", .exact("2.0.0")),
          ],
          targets: [
              .executableTarget(
                  name: "xcbeautify",
                  dependencies: [
                      "XcbeautifyLib",
                      "SwiftGen",
                      .product(name: "ArgumentParser", package: "swift-argument-parser"),
                      .product(name: "FBLPromises", package: "Promises"),
                      "OCMock",
                      "libwebp",
                      .product(name: "MetricsReporter", package: "MetricsReporter"),
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

      expected_package_manifest_content = """
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
              .package(
                url: "https://github.com/google/promises.git",
                "2.4.0" ..< "3.0.0"
              ),
              .package(
                name: "ocmock",
                url: "https://github.com/erikdoe/ocmock.git",
                .revision("c5eeaa6dde7c308a5ce48ae4d4530462dd3a1110")
              ),
              .package(name: "libwebp-Xcode",
                       url: "https://github.com/SDWebImage/libwebp-Xcode",
                       from: "1.1.0"),
              .package(name: "metrics-reporter-ios", url: "https://github.com/rudderlabs/metrics-reporter-ios", .exact("2.0.0")),
          ],
          targets: [
              .executableTarget(
                  name: "xcbeautify",
                  dependencies: [
                      "XcbeautifyLib",
                      .product(name: "SwiftGen", package: "SwiftGen"),
                      .product(name: "ArgumentParser", package: "swift-argument-parser"),
                      .product(name: "FBLPromises", package: "promises"),
                      .product(name: "ocmock", package: "ocmock"),
                      .product(name: "libwebp-Xcode", package: "libwebp-Xcode"),
                      .product(name: "MetricsReporter", package: "metrics-reporter-ios"),
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
      """

      stub(Storage, :put_object, fn
        "registry/swift/alamofire/alamofire/5.10.2/Package.swift", ^expected_package_manifest_content ->
          :ok

        "registry/swift/alamofire/alamofire/5.10.2/Package@swift-5.9.swift", ^expected_package_manifest_content ->
          :ok

        "registry/swift/alamofire/alamofire/5.10.2/source_archive.zip", _ ->
          :ok
      end)

      stub(VCS, :get_source_archive_by_tag_and_repository_full_handle, fn _ ->
        {:ok, "/tmp/source_archive.zip"}
      end)

      stub(System, :cmd, fn _, _ -> {"", 0} end)
      stub(System, :cmd, fn _, _, _ -> {"", 0} end)

      stub(File, :ls!, fn path ->
        if String.ends_with?(path, "Alamofire") do
          ["Package.swift", "Package@swift-5.9.swift", "File.swift"]
        else
          ["Alamofire"]
        end
      end)

      expect(
        File,
        :write!,
        2,
        fn path, content ->
          assert String.ends_with?(path, "Package.swift") or
                   String.ends_with?(path, "Package@swift-5.9.swift")

          assert content == expected_package_manifest_content
        end
      )

      stub(File, :read!, fn _ ->
        initial_package_manifest_content
      end)

      stub(VCS, :get_repository_content, fn
        _, [reference: "v5.10.2", path: "root/Package.swift"] ->
          {:ok, %Content{path: "root/Package.swift", content: initial_package_manifest_content}}

        _, [reference: "v5.10.2", path: "root/Package@swift-5.9.swift"] ->
          {:ok,
           %Content{
             path: "root/Package@swift-5.9.swift",
             content: initial_package_manifest_content
           }}

        _, _ ->
          {:ok, [%Content{path: "root/Package.swift"}, %Content{path: "root/Package@swift-5.9.swift"}]}
      end)

      # When
      got = Packages.create_missing_package_releases(%{package: package, token: "github_token"})

      # Then
      assert Enum.map(got, & &1.version) == [
               "5.10.2"
             ]
    end

    test "creates missing package releases when Package.swift manifest has header search paths" do
      # Given
      package =
        PackagesFixtures.package_fixture(
          scope: "pinterest",
          name: "PINRemoteImage",
          preload: [:package_releases]
        )

      stub(VCS, :get_tags, fn _ ->
        [
          %Tag{name: "5.10.2"}
        ]
      end)

      initial_package_manifest_content = """
      // swift-tools-version:5.3
      // The swift-tools-version declares the minimum version of Swift required to build this package.

      import PackageDescription

      let package = Package(
          name: "PINRemoteImage",
          dependencies: [
              .package(url: "https://github.com/pinterest/PINCache.git", from: "3.0.2"),
          ],
          targets: [
              .target(
                  name: "PINRemoteImage",
                  dependencies: ["PINCache"],
                  path: "Source/Classes",
                  publicHeadersPath: "include",
                  cSettings: [
                      .headerSearchPath("PINCache"),
                      ]),
          ]
      )
      """

      expected_package_manifest_content = """
      // swift-tools-version:5.3
      // The swift-tools-version declares the minimum version of Swift required to build this package.

      import PackageDescription

      let package = Package(
          name: "PINRemoteImage",
          dependencies: [
              .package(url: "https://github.com/pinterest/PINCache.git", from: "3.0.2"),
          ],
          targets: [
              .target(
                  name: "PINRemoteImage",
                  dependencies: [.product(name: "PINCache", package: "PINCache")],
                  path: "Source/Classes",
                  publicHeadersPath: "include",
                  cSettings: [
                      .headerSearchPath("PINCache"),
                      ]),
          ]
      )
      """

      stub(Storage, :put_object, fn
        "registry/swift/pinterest/pinremoteimage/5.10.2/Package.swift", _ ->
          :ok

        "registry/swift/pinterest/pinremoteimage/5.10.2/source_archive.zip", _ ->
          :ok
      end)

      stub(VCS, :get_source_archive_by_tag_and_repository_full_handle, fn _ ->
        {:ok, "/tmp/source_archive.zip"}
      end)

      stub(System, :cmd, fn _, _ -> {"", 0} end)
      stub(System, :cmd, fn _, _, _ -> {"", 0} end)

      stub(File, :ls!, fn path ->
        if String.ends_with?(path, ".zip") do
          ["Alamofire"]
        else
          ["Package.swift"]
        end
      end)

      expect(File, :write!, fn path, content ->
        assert String.ends_with?(path, "Package.swift")
        assert content == expected_package_manifest_content
      end)

      stub(File, :read!, fn _ ->
        initial_package_manifest_content
      end)

      stub(VCS, :get_repository_content, fn
        _, [reference: _, path: "Package.swift"] ->
          {:ok, %Content{content: "content", path: "Package.swift"}}

        _, _ ->
          {:ok, [%Content{path: "Package.swift"}]}
      end)

      # When
      got = Packages.create_missing_package_releases(%{package: package, token: "github_token"})

      # Then
      assert Enum.map(got, & &1.version) == [
               "5.10.2"
             ]
    end

    test "creates missing package releases when Package.swift manifest has .byName references" do
      # Given
      package =
        PackagesFixtures.package_fixture(
          scope: "pinterest",
          name: "PINRemoteImage",
          preload: [:package_releases]
        )

      stub(VCS, :get_tags, fn _ ->
        [
          %Tag{name: "5.10.2"}
        ]
      end)

      initial_package_manifest_content = """
      // swift-tools-version:5.3
      // The swift-tools-version declares the minimum version of Swift required to build this package.

      import PackageDescription

      let package = Package(
          name: "PINRemoteImage",
          dependencies: [
              .package(url: "https://github.com/pinterest/PINCache.git", from: "3.0.2"),
          ],
          targets: [
              .target(
                  name: "PINRemoteImage",
                  dependencies: [
                    .byName(name: "PINCache"),
                  ]
          ]
      )
      """

      expected_package_manifest_content = """
      // swift-tools-version:5.3
      // The swift-tools-version declares the minimum version of Swift required to build this package.

      import PackageDescription

      let package = Package(
          name: "PINRemoteImage",
          dependencies: [
              .package(url: "https://github.com/pinterest/PINCache.git", from: "3.0.2"),
          ],
          targets: [
              .target(
                  name: "PINRemoteImage",
                  dependencies: [
                    .product(name: "PINCache", package: "PINCache"),
                  ]
          ]
      )
      """

      stub(Storage, :put_object, fn
        "registry/swift/pinterest/pinremoteimage/5.10.2/Package.swift", _ ->
          :ok

        "registry/swift/pinterest/pinremoteimage/5.10.2/source_archive.zip", _ ->
          :ok
      end)

      stub(VCS, :get_source_archive_by_tag_and_repository_full_handle, fn _ ->
        {:ok, "/tmp/source_archive.zip"}
      end)

      stub(System, :cmd, fn _, _ -> {"", 0} end)
      stub(System, :cmd, fn _, _, _ -> {"", 0} end)

      stub(File, :ls!, fn path ->
        if String.ends_with?(path, ".zip") do
          ["Alamofire"]
        else
          ["Package.swift"]
        end
      end)

      expect(File, :write!, fn path, content ->
        assert String.ends_with?(path, "Package.swift")
        assert content == expected_package_manifest_content
      end)

      stub(File, :read!, fn _ ->
        initial_package_manifest_content
      end)

      stub(VCS, :get_repository_content, fn
        _, [reference: _, path: "Package.swift"] ->
          {:ok, %Content{content: "content", path: "Package.swift"}}

        _, _ ->
          {:ok, [%Content{path: "Package.swift"}]}
      end)

      # When
      got = Packages.create_missing_package_releases(%{package: package, token: "github_token"})

      # Then
      assert Enum.map(got, & &1.version) == [
               "5.10.2"
             ]
    end

    test "creates missing package with Package.swift for specific Swift versions" do
      # Given
      package =
        PackagesFixtures.package_fixture(
          scope: "Alamofire",
          name: "Alamofire",
          preload: [:package_releases]
        )

      stub(Storage, :put_object, fn
        "registry/swift/alamofire/alamofire/5.10.2/Package.swift", _ -> :ok
        "registry/swift/alamofire/alamofire/5.10.2/Package@swift-5.swift", _ -> :ok
        "registry/swift/alamofire/alamofire/5.10.2/Package@swift-5.8.swift", _ -> :ok
        "registry/swift/alamofire/alamofire/5.10.2/Package@swift-5.7.2.swift", _ -> :ok
        "registry/swift/alamofire/alamofire/5.10.2/source_archive.zip", _ -> :ok
      end)

      stub(VCS, :get_tags, fn _ ->
        [
          %Tag{name: "5.10.2"}
        ]
      end)

      stub(VCS, :get_source_archive_by_tag_and_repository_full_handle, fn _ ->
        {:ok, "/tmp/source_archive.zip"}
      end)

      stub(System, :cmd, fn _, _ -> {"", 0} end)
      stub(System, :cmd, fn _, _, _ -> {"", 0} end)

      stub(File, :ls!, fn _ ->
        ["Alamofire"]
      end)

      stub(File, :read!, fn _ ->
        "content"
      end)

      stub(VCS, :get_repository_content, fn
        _, [reference: _, path: "Package.swift"] ->
          {:ok,
           %Content{
             content: "// swift-tools-version: 6.0\n rest of content",
             path: "Package.swift"
           }}

        _, [reference: _, path: "Package@swift-5.swift"] ->
          {:ok,
           %Content{
             content:
               ~s{// swift-tools-version:5.9\n//\n//  Package@swift-5.9.swift\n//\n//  Copyright (c) 2022 Alamofire Software Foundation (http://alamofire.org/)\n//\n//  Permission is hereby granted, free of charge, to any person obtaining a copy\n//  of this software and associated documentation files (the "Software"), to deal\n//  in the Software without restriction, including without limitation the rights\n//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell\n//  copies of the Software, and to permit persons to whom the Software is\n//  furnished to do so, subject to the following conditions:\n//\n//  The above copyright notice and this permission notice shall be included in\n//  all copies or substantial portions of the Software.\n//\n//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR\n//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,\n//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE\n//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER\n//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,\n//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN\n//  THE SOFTWARE.\n//\n\nimport PackageDescription\n\nlet package = Package(name: "Alamofire",\n                      platforms: [.macOS(.v10_13),\n                                  .iOS(.v12),\n                                  .tvOS(.v12),\n                                  .watchOS(.v4)],\n                      products: [\n                          .library(name: "Alamofire", targets: ["Alamofire"]),\n                          .library(name: "AlamofireDynamic", type: .dynamic, targets: ["Alamofire"])\n                      ],\n                      targets: [.target(name: "Alamofire",\n                                        path: "Source",\n                                        exclude: ["Info.plist"],\n                                        resources: [.process("PrivacyInfo.xcprivacy")],\n                                        linkerSettings: [.linkedFramework("CFNetwork",\n                                                                          .when(platforms: [.iOS,\n                                                                                            .macOS,\n                                                                                            .tvOS,\n                                                                                            .watchOS]))]),\n                                .testTarget(name: "AlamofireTests",\n                                            dependencies: ["Alamofire"],\n                                            path: "Tests",\n                                            exclude: ["Info.plist", "Test Plans"],\n                                            resources: [.process("Resources")])],\n                      swiftLanguageVersions: [.v5])\n},
             path: "Package.swift"
           }}

        _, [reference: _, path: "Package@swift-5.8.swift"] ->
          {:ok,
           %Content{
             content: "// swift-tools-version: 5.8.1\n rest of content",
             path: "Package.swift"
           }}

        _, [reference: _, path: "Package@swift-5.7.2.swift"] ->
          {:ok,
           %Content{
             content: "// swift-tools-version: 5.7.2\n rest of content",
             path: "Package.swift"
           }}

        _, _ ->
          {:ok,
           [
             %Content{path: "Package.swift"},
             %Content{path: "Package@swift-5.swift"},
             %Content{path: "Package@swift-5.8.swift"},
             %Content{path: "Package@swift-5.7.2.swift"}
           ]}
      end)

      stub(Base64, :decode, fn "content" -> "content" end)

      # When
      [got] =
        %{package: package, token: "github_token"}
        |> Packages.create_missing_package_releases()
        |> Repo.preload(:manifests)

      # Then
      assert Enum.count(got.manifests) == 4
      sorted_package_manifests = Enum.sort_by(got.manifests, & &1.swift_tools_version)

      assert Enum.map(sorted_package_manifests, & &1.swift_tools_version) == [
               "5.7.2",
               "5.8.1",
               "5.9",
               "6.0"
             ]

      assert Enum.map(sorted_package_manifests, & &1.swift_version) == [
               "5.7.2",
               "5.8",
               "5",
               nil
             ]
    end

    test "does not upload Package.swift if none exists" do
      # Given
      package =
        PackagesFixtures.package_fixture(
          scope: "My",
          name: "Package",
          preload: [:package_releases]
        )

      stub(Storage, :put_object, fn
        "registry/swift/my/package/5.10.2/source_archive.zip", _ -> :ok
      end)

      stub(VCS, :get_tags, fn _ ->
        [
          %Tag{name: "5.10.2"}
        ]
      end)

      stub(VCS, :get_repository_content, fn
        _, _ ->
          {:ok, [%Content{path: "SomeFile.swift"}]}
      end)

      stub(VCS, :get_source_archive_by_tag_and_repository_full_handle, fn _ ->
        {:ok, "/tmp/source_archive.zip"}
      end)

      stub(System, :cmd, fn _, _ -> {"", 0} end)
      stub(System, :cmd, fn _, _, _ -> {"", 0} end)

      stub(File, :ls!, fn path ->
        if String.ends_with?(path, ".zip") do
          ["Alamofire"]
        else
          ["File.swift"]
        end
      end)

      stub(File, :read!, fn _ ->
        "content"
      end)

      # When
      got = Packages.create_missing_package_releases(%{package: package, token: "github_token"})

      # Then
      assert Enum.map(got, & &1.version) == [
               "5.10.2"
             ]
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
