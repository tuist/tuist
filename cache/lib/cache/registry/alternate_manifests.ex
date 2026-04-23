defmodule Cache.Registry.AlternateManifests do
  @moduledoc """
  Discovers `Package@swift-X.Y.swift` alternate manifests in S3 for a registry
  release.

  Used by the registry controller as a fallback when a release's metadata is
  missing the `manifests` field (e.g., releases synced before manifest indexing
  was added). Without this fallback, SwiftPM never sees the alternates and may
  pick a root `Package.swift` that the active toolchain cannot compile.

  Results are cached with a short TTL so dependency resolution does not list
  S3 on every manifest fetch.

  `swift_tools_version` is intentionally not populated — the Link header
  attribute is optional per the Swift Package Registry spec and SwiftPM picks
  alternates by filename. Skipping the per-file content fetch keeps the read
  path to a single S3 list call.
  """

  alias Cache.Config
  alias Cache.Registry.KeyNormalizer

  require Logger

  @cache_name :registry_alternate_manifests_cache
  @ttl to_timeout(minute: 10)
  @alternate_manifest_regex ~r/\APackage@swift-(\d+)(?:\.(\d+))?(?:\.(\d+))?\.swift\z/

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
      |> Stream.map(fn %{key: key} -> Path.basename(key) end)
      |> Stream.flat_map(&filename_to_descriptor/1)
      |> Enum.to_list()
    rescue
      error ->
        Logger.warning(
          "Failed to discover alternate manifests for #{scope}/#{name}@#{version}: " <>
            inspect(error)
        )

        []
    end
  end

  defp filename_to_descriptor(filename) do
    case Regex.run(@alternate_manifest_regex, filename) do
      [_, major] ->
        [%{"swift_version" => major, "swift_tools_version" => nil}]

      [_, major, minor] ->
        [%{"swift_version" => "#{major}.#{minor}", "swift_tools_version" => nil}]

      [_, major, minor, patch] ->
        [%{"swift_version" => "#{major}.#{minor}.#{patch}", "swift_tools_version" => nil}]

      _ ->
        []
    end
  end
end
