defmodule Cache.Registry.AlternateManifests do
  @moduledoc """
  Discovers `Package@swift-X.Y.swift` alternate manifests in S3 for a registry
  release.

  Used by the registry controller as a fallback when a release's metadata is
  missing the `manifests` field (e.g., releases synced before manifest indexing
  was added). Without this fallback, SwiftPM never sees the alternates and may
  pick a root `Package.swift` that the active toolchain cannot compile.

  Each discovered manifest's `swift_tools_version` is read from the file
  content. Although the spec marks the Link header attribute as optional,
  SwiftPM (verified with 6.2.3) only selects alternates that advertise
  `swift-tools-version`, so the read is required for the fallback to be useful.

  Results are cached with a short TTL so dependency resolution does not list
  and fetch from S3 on every manifest request.
  """

  alias Cache.Config
  alias Cache.Registry.KeyNormalizer
  alias Cache.Registry.ManifestVariants

  require Logger

  @cache_name :registry_alternate_manifests_cache
  @ttl to_timeout(minute: 10)
  def child_spec(_opts) do
    %{
      id: __MODULE__,
      start: {Cachex, :start_link, [cache_name(), []]}
    }
  end

  def cache_name, do: @cache_name

  def list(scope, name, version, opts \\ []) do
    cache_name = Keyword.get(opts, :cache_name, cache_name())
    key = {scope, name, version}

    case Cachex.get(cache_name, key) do
      {:ok, nil} ->
        manifests = discover(scope, name, version)
        Cachex.put(cache_name, key, manifests, ttl: @ttl)
        manifests

      {:ok, manifests} ->
        manifests

      _ ->
        discover(scope, name, version)
    end
  end

  defp discover(scope, name, version) do
    bucket = Config.registry_bucket()

    prefix =
      KeyNormalizer.package_object_key(%{scope: scope, name: name}, version: version) <> "/"

    try do
      bucket
      |> ExAws.S3.list_objects_v2(prefix: prefix)
      |> ExAws.stream!()
      |> Stream.map(fn %{key: key} -> {key, Path.basename(key)} end)
      |> Enum.to_list()
      |> descriptors(bucket, scope, name, version)
    rescue
      error ->
        Logger.warning(
          "Failed to discover alternate manifests for #{scope}/#{name}@#{version}: " <>
            inspect(error)
        )

        []
    end
  end

  defp descriptors(objects, bucket, scope, name, version) do
    alternate_objects =
      Enum.filter(objects, fn {_key, filename} -> ManifestVariants.alternate_manifest?(filename) end)

    if alternate_objects == [] do
      []
    else
      descriptors_with_alternates(objects, alternate_objects, bucket, scope, name, version)
    end
  end

  defp descriptors_with_alternates(objects, alternate_objects, bucket, scope, name, version) do
    default_descriptor =
      objects
      |> Enum.find(fn {_key, filename} -> filename == "Package.swift" end)
      |> case do
        nil -> []
        {key, filename} -> descriptor_for(bucket, key, filename, scope, name, version)
      end

    alternates =
      Enum.flat_map(alternate_objects, fn {key, filename} ->
        descriptor_for(bucket, key, filename, scope, name, version)
      end)

    ManifestVariants.linkable_alternates(default_descriptor ++ alternates)
  end

  defp descriptor_for(bucket, key, filename, scope, name, version) do
    case fetch_content(bucket, key) do
      {:ok, content} ->
        [
          %{
            "swift_version" => filename_swift_version(filename),
            "swift_tools_version" => ManifestVariants.swift_tools_version(content)
          }
        ]

      {:error, reason} ->
        Logger.warning(
          "Failed to fetch alternate manifest #{key} for #{scope}/#{name}@#{version}: " <>
            inspect(reason)
        )

        []
    end
  end

  defp fetch_content(bucket, key) do
    case bucket
         |> ExAws.S3.get_object(key)
         |> ExAws.request() do
      {:ok, %{body: body}} -> {:ok, body}
      {:error, reason} -> {:error, reason}
    end
  end

  defp filename_swift_version("Package.swift"), do: nil
  defp filename_swift_version(filename), do: ManifestVariants.filename_swift_version(filename)
end
