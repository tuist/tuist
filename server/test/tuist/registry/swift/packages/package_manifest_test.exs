defmodule Tuist.Registry.Swift.Packages.PackageManifestTest do
  use TuistTestSupport.Cases.DataCase

  alias Tuist.Registry.Swift.Packages.PackageManifest
  alias TuistTestSupport.Fixtures.Registry.Swift.PackagesFixtures

  describe "create_changeset/1" do
    test "ensures package_release_id is present" do
      # Given
      package_manifest = %PackageManifest{}

      # When
      got = PackageManifest.create_changeset(package_manifest, %{})

      # Then
      assert "can't be blank" in errors_on(got).package_release_id
    end

    test "is valid when contains all necessary attributes" do
      # Given
      package_release = PackagesFixtures.package_release_fixture()
      package_manifest = %PackageManifest{}

      # When
      got =
        PackageManifest.create_changeset(package_manifest, %{
          package_release_id: package_release.id
        })

      # Then
      assert got.valid?
    end

    test "is valid when contains all attributes" do
      # Given
      package_release = PackagesFixtures.package_release_fixture()
      package_manifest = %PackageManifest{}

      # When
      got =
        PackageManifest.create_changeset(package_manifest, %{
          package_release_id: package_release.id,
          swift_version: "5.3",
          swift_tools_version: "5.3.1"
        })

      # Then
      assert got.valid?
    end

    test "ensures that the package_release_id and swift_version are unique" do
      # Given
      package_manifest = %PackageManifest{}
      package_release = PackagesFixtures.package_release_fixture()

      changeset =
        PackageManifest.create_changeset(package_manifest, %{
          package_release_id: package_release.id,
          swift_version: "5.3",
          swift_tools_version: "5.3.1"
        })

      # When
      {:ok, _} = Repo.insert(changeset)

      {:error, got} =
        package_manifest
        |> PackageManifest.create_changeset(%{
          package_release_id: package_release.id,
          swift_version: "5.3",
          swift_tools_version: "5.3.1"
        })
        |> Repo.insert()

      # Then
      assert "has already been taken" in errors_on(got).package_release_id
    end
  end
end
