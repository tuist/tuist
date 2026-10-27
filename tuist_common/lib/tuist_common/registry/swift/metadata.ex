defmodule TuistCommon.Registry.Swift.Metadata do
  @moduledoc """
  Shared contract for Swift package registry metadata stored in object storage.

  Both the server sync runtime and the registry read frontend use this module
  so metadata keys, JSON encoding, JSON decoding, and version sanitization stay
  in one place.

  Metadata is stored at `registry/metadata/{scope}/{name}/index.json`.
  """

  alias TuistCommon.Registry.Swift.KeyNormalizer

  @metadata_key_regex ~r{^registry/metadata/([^/]+)/([^/]+)/index\.json$}

  @doc """
  Builds the normalized object-storage key for a package metadata file.
  """
  def s3_key(scope, name) when is_binary(scope) and is_binary(name) do
    {scope, name} = KeyNormalizer.normalize_scope_name(scope, name)
    "registry/metadata/#{scope}/#{name}/index.json"
  end

  @doc """
  Decodes and sanitizes a package metadata JSON document.
  """
  def decode_package(body) when is_binary(body) do
    case JSON.decode(body) do
      {:ok, metadata} when is_map(metadata) -> {:ok, sanitize_package(metadata)}
      _ -> {:error, :invalid_metadata}
    end
  end

  @doc """
  Sanitizes and encodes a package metadata document as JSON.
  """
  def encode_package!(metadata) when is_map(metadata) do
    metadata
    |> sanitize_package()
    |> JSON.encode!()
  end

  @doc """
  Keeps only normalized registry storage versions in release maps.
  """
  def sanitize_package(metadata) when is_map(metadata) do
    metadata
    |> sanitize_versions("releases")
    |> sanitize_versions("skipped_releases")
  end

  @doc """
  Parses a package metadata object key into `{scope, name}`.
  """
  def parse_s3_key(key) when is_binary(key) do
    case Regex.run(@metadata_key_regex, key) do
      [_, scope, name] -> {scope, name}
      _ -> nil
    end
  end

  defp sanitize_versions(metadata, key) do
    case Map.fetch(metadata, key) do
      {:ok, versions} when is_map(versions) ->
        filtered_versions =
          Enum.reduce(versions, %{}, fn {version, value}, acc ->
            if KeyNormalizer.valid_storage_version?(version) do
              Map.put(acc, version, value)
            else
              acc
            end
          end)

        Map.put(metadata, key, filtered_versions)

      _ ->
        metadata
    end
  end
end
