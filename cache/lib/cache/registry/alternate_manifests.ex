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
        discover_and_maybe_cache(cache_name, key, scope, name, version)

      {:ok, manifests} ->
        manifests

      _ ->
        {_status, manifests} = discover(scope, name, version)
        manifests
    end
  end

  defp discover_and_maybe_cache(cache_name, key, scope, name, version) do
    case discover(scope, name, version) do
      {:ok, manifests} ->
        Cachex.put(cache_name, key, manifests, ttl: @ttl)
        manifests

      {:error, manifests} ->
        manifests
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

        {:error, []}
    end
  end

  defp descriptors(objects, bucket, scope, name, version) do
    alternate_objects =
      Enum.filter(objects, fn {_key, filename} -> ManifestVariants.alternate_manifest?(filename) end)

    if alternate_objects == [],
      do: {:ok, []},
      else: descriptors_with_alternates(objects, alternate_objects, bucket, scope, name, version)
  end

  defp descriptors_with_alternates(objects, alternate_objects, bucket, scope, name, version) do
    default_object = Enum.find(objects, fn {_key, filename} -> filename == "Package.swift" end)

    case default_descriptor_for(default_object, bucket, scope, name, version) do
      {:ok, default_descriptor} ->
        alternates =
          Enum.flat_map(alternate_objects, fn {key, filename} ->
            descriptor_for(bucket, key, filename, scope, name, version)
          end)

        {:ok, ManifestVariants.linkable_alternates(default_descriptor ++ alternates)}

      {:error, _reason} ->
        {:error, []}
    end
  end

  defp default_descriptor_for(nil, _bucket, _scope, _name, _version), do: {:ok, []}

  defp default_descriptor_for({key, filename}, bucket, scope, name, version) do
    case fetch_content(bucket, key) do
      {:ok, content} ->
        {:ok,
         [
           %{
             "swift_version" => filename_swift_version(filename),
             "swift_tools_version" => ManifestVariants.swift_tools_version(content)
           }
         ]}

      {:error, reason} ->
        Logger.warning(
          "Failed to fetch default manifest #{key} for #{scope}/#{name}@#{version}: " <>
            inspect(reason)
        )

        {:error, reason}
    end
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
