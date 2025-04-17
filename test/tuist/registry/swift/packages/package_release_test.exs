defmodule Tuist.Registry.Swift.Packages.PackageReleaseTest do
  use TuistTestSupport.Cases.DataCase

  alias Tuist.Registry.Swift.Packages.PackageRelease
  alias TuistTestSupport.Fixtures.Registry.Swift.PackagesFixtures

  describe "create_changeset/1" do
    test "ensures package_id is present" do
      # Given
      package_release = %PackageRelease{}

      # When
      got = PackageRelease.create_changeset(package_release, %{})

      # Then
      assert "can't be blank" in errors_on(got).package_id
    end

    test "ensures checksum is present" do
      # Given
      package_release = %PackageRelease{}

      # When
      got = PackageRelease.create_changeset(package_release, %{})

      # Then
      assert "can't be blank" in errors_on(got).checksum
    end

    test "ensures version is present" do
      # Given
      package_release = %PackageRelease{}

      # When
      got = PackageRelease.create_changeset(package_release, %{})

      # Then
      assert "can't be blank" in errors_on(got).version
    end

    test "is valid when contains all necessary attributes" do
      # Given
      package_release = %PackageRelease{}
      package = PackagesFixtures.package_fixture()

      # When
      got =
        PackageRelease.create_changeset(package_release, %{
          package_id: package.id,
          checksum: "Checksum",
          version: "Version"
        })

      # Then
      assert got.valid?
    end

    test "ensures that the package_id and version are unique" do
      # Given
      package_release = %PackageRelease{}
      package = PackagesFixtures.package_fixture()

      changeset =
        PackageRelease.create_changeset(package_release, %{
          package_id: package.id,
          checksum: "Checksum",
          version: "Version"
        })

      # When
      {:ok, _} = Repo.insert(changeset)

      {:error, got} =
        %PackageRelease{}
        |> PackageRelease.create_changeset(%{
          package_id: package.id,
          checksum: "Checksum",
          version: "Version"
        })
        |> Repo.insert()

      # Then
      assert "has already been taken" in errors_on(got).package_id
    end
  end
end
