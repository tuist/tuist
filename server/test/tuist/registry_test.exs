defmodule Tuist.RegistryTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.Registry
  alias Tuist.Registry.Swift.Metadata
  alias Tuist.Registry.Swift.SwiftPackageIndex

  setup :set_mimic_from_context
  setup :verify_on_exit!

  test "returns a package with available and skipped versions in descending order" do
    expect(SwiftPackageIndex, :list_packages, fn nil ->
      {:ok, [package("apple", "swift-argument-parser")]}
    end)

    expect(Metadata, :get_package, fn "apple", "swift-argument-parser" ->
      {:ok,
       %{
         "releases" => %{
           "1.2.3" => %{"checksum" => "abc123"},
           "2.0.0" => %{"checksum" => "def456"}
         },
         "skipped_releases" => %{
           "1.0.0" => %{"reason" => "missing_manifests"}
         }
       }}
    end)

    assert {:ok, package} = Registry.get_swift_package("apple", "swift-argument-parser")

    assert package.versions == [
             %{version: "2.0.0", status: :available, detail: "def456"},
             %{version: "1.2.3", status: :available, detail: "abc123"},
             %{version: "1.0.0", status: :skipped, detail: "missing_manifests"}
           ]
  end

  test "does not raise on non-SemVer version keys and sorts them after valid versions" do
    expect(SwiftPackageIndex, :list_packages, fn nil ->
      {:ok, [package("apple", "swift-argument-parser")]}
    end)

    expect(Metadata, :get_package, fn "apple", "swift-argument-parser" ->
      {:ok,
       %{
         "releases" => %{
           "1.2.3" => %{"checksum" => "abc123"},
           "not-a-semver" => %{"checksum" => "def456"}
         }
       }}
    end)

    assert {:ok, package} = Registry.get_swift_package("apple", "swift-argument-parser")

    assert package.versions == [
             %{version: "1.2.3", status: :available, detail: "abc123"},
             %{version: "not-a-semver", status: :available, detail: "def456"}
           ]
  end

  test "returns a catalog package without versions when metadata does not exist" do
    expect(SwiftPackageIndex, :list_packages, fn nil ->
      {:ok, [package("apple", "swift-argument-parser")]}
    end)

    expect(Metadata, :get_package, fn "apple", "swift-argument-parser" ->
      {:error, :not_found}
    end)

    assert {:ok, %{versions: []}} =
             Registry.get_swift_package("apple", "swift-argument-parser")
  end

  test "returns not found when the package is not in the catalog" do
    expect(SwiftPackageIndex, :list_packages, fn nil -> {:ok, []} end)

    assert {:error, :not_found} = Registry.get_swift_package("unknown", "package")
  end

  defp package(scope, name) do
    %{
      scope: scope,
      name: name,
      repository_full_handle: "#{scope}/#{name}"
    }
  end
end
