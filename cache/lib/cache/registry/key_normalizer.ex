defmodule Cache.Registry.KeyNormalizer do
  @moduledoc """
  Normalizes registry package keys to match the server's key format.

  This module ensures that cache keys for Swift package registry artifacts
  are consistent with the server's storage format, enabling proper S3
  synchronization via S3TransferWorker.
  """

  @doc """
  Normalizes a scope by downcasing it.

  ## Examples

      iex> Cache.Registry.KeyNormalizer.normalize_scope("Apple")
      "apple"

      iex> Cache.Registry.KeyNormalizer.normalize_scope("SWIFT")
      "swift"
  """
  def normalize_scope(scope) when is_binary(scope) do
    String.downcase(scope)
  end

  @doc """
  Normalizes a version string to semantic version format matching the server.

  - Strips leading "v" prefix
  - Adds trailing zeros for incomplete versions (1 -> 1.0.0, 1.2 -> 1.2.0)
  - Converts pre-release dot separator to plus (1.0.0-alpha.1 -> 1.0.0-alpha+1)

  ## Examples

      iex> Cache.Registry.KeyNormalizer.normalize_version("v1.2.3")
      "1.2.3"

      iex> Cache.Registry.KeyNormalizer.normalize_version("1")
      "1.0.0"

      iex> Cache.Registry.KeyNormalizer.normalize_version("1.2")
      "1.2.0"

      iex> Cache.Registry.KeyNormalizer.normalize_version("1.0.0-alpha.1")
      "1.0.0-alpha+1"

      iex> Cache.Registry.KeyNormalizer.normalize_version("v2.0.0-beta.2")
      "2.0.0-beta+2"
  """
  def normalize_version(version) when is_binary(version) do
    version = String.trim_leading(version, "v")

    case String.split(version, "-", parts: 2) do
      [base, prerelease] ->
        prerelease_with_plus = String.replace(prerelease, ".", "+")
        base = add_trailing_semantic_version_zeros(base)
        "#{base}-#{prerelease_with_plus}"

      [base] ->
        add_trailing_semantic_version_zeros(base)
    end
  end

  defp add_trailing_semantic_version_zeros(version) do
    case String.split(version, ".") do
      [major] -> "#{major}.0.0"
      [major, minor] -> "#{major}.#{minor}.0"
      _ -> version
    end
  end

  @doc """
  Constructs an S3-compatible object key for a registry package artifact.

  The key format matches the server's `package_object_key/2` function exactly:
  `registry/swift/{scope}/{name}/{version}/{path}`

  All components are downcased and the version is normalized.

  ## Options

    * `:version` - The package version (will be normalized)
    * `:path` - The file path within the package (e.g., "source_archive.zip")

  ## Examples

      iex> Cache.Registry.KeyNormalizer.package_object_key(%{scope: "Apple", name: "Parser"}, version: "v1.2", path: "source_archive.zip")
      "registry/swift/apple/parser/1.2.0/source_archive.zip"

      iex> Cache.Registry.KeyNormalizer.package_object_key(%{scope: "swift", name: "nio"}, version: "2.0.0", path: "Package.swift")
      "registry/swift/swift/nio/2.0.0/Package.swift"

      iex> Cache.Registry.KeyNormalizer.package_object_key(%{scope: "Apple", name: "Parser"}, [])
      "registry/swift/apple/parser"
  """
  def package_object_key(%{scope: scope, name: name}, opts \\ []) do
    version = Keyword.get(opts, :version)
    path = Keyword.get(opts, :path)

    object_key = "registry/swift/#{String.downcase(scope)}/#{String.downcase(name)}"

    object_key =
      if is_nil(version) do
        object_key
      else
        object_key <> "/#{normalize_version(version)}"
      end

    if is_nil(path) do
      object_key
    else
      object_key <> "/#{path}"
    end
  end
end
