defmodule Tuist.Registry.Swift.Packages.PackageTest do
  alias Tuist.Registry.Swift.Packages.Package
  use Tuist.DataCase

  describe "create_changeset/1" do
    test "ensures a scope is present" do
      # Given
      package = %Package{}

      # When
      got = Package.create_changeset(package, %{})

      # Then
      assert "can't be blank" in errors_on(got).scope
    end

    test "ensures a name is present" do
      # Given
      package = %Package{}

      # When
      got = Package.create_changeset(package, %{})

      # Then
      assert "can't be blank" in errors_on(got).name
    end

    test "is valid when contains all necessary attributes" do
      # Given
      package = %Package{}

      # When
      got = Package.create_changeset(package, %{scope: "Scope", name: "Name"})

      # Then
      assert got.valid?
    end

    test "ensures that the scope and name are unique" do
      # Given
      changeset =
        Package.create_changeset(%Package{}, %{
          scope: "Scope",
          name: "Name"
        })

      # When
      {:ok, _} = Repo.insert(changeset)

      {:error, got} =
        Package.create_changeset(%Package{}, %{
          scope: "Scope",
          name: "Name"
        })
        |> Repo.insert()

      # Then
      assert "has already been taken" in errors_on(got).scope
    end
  end
end
