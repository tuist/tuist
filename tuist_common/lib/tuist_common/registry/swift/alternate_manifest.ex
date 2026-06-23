defmodule TuistCommon.Registry.Swift.AlternateManifest do
  @moduledoc """
  Shared parser for Swift package registry alternate manifests.

  The sync writer uses this while indexing manifests, and the registry read
  frontend uses it for the fallback path that discovers alternates from object
  storage when older metadata does not include manifest descriptors yet.
  """

  @alternate_manifest_regex ~r/\APackage@swift-(\d+)(?:\.(\d+))?(?:\.(\d+))?\.swift\z/
  @swift_tools_version_regex ~r/^\/\/ swift-tools-version:\s?(\d+)(?:\.(\d+))?(?:\.(\d+))?/

  def default_filename, do: "Package.swift"

  def alternate_filename?(filename) when is_binary(filename) do
    Regex.match?(@alternate_manifest_regex, filename)
  end

  def registry_manifest_path?(path) when is_binary(path) do
    filename = Path.basename(path)
    filename == default_filename() or alternate_filename?(filename)
  end

  def swift_version_from_filename(filename) when is_binary(filename) do
    case Regex.run(@alternate_manifest_regex, filename) do
      [_, major] -> major
      [_, major, minor] -> "#{major}.#{minor}"
      [_, major, minor, patch] -> "#{major}.#{minor}.#{patch}"
      _ -> nil
    end
  end

  def swift_tools_version(content) when is_binary(content) do
    case Regex.run(@swift_tools_version_regex, content) do
      [_, major] -> major
      [_, major, minor] -> "#{major}.#{minor}"
      [_, major, minor, patch] -> "#{major}.#{minor}.#{patch}"
      _ -> nil
    end
  end

  def deduplicate_by_tools_version(manifests) when is_list(manifests) do
    defaults = Enum.filter(manifests, &is_nil(&1["swift_version"]))
    defaults ++ linkable_alternates(manifests)
  end

  def linkable_alternates(manifests) when is_list(manifests) do
    default_tools_versions =
      manifests
      |> Enum.filter(&is_nil(&1["swift_version"]))
      |> Enum.map(&canonical_tools_version(&1["swift_tools_version"]))
      |> Enum.reject(&is_nil/1)
      |> MapSet.new()

    manifests
    |> Enum.reject(&is_nil(&1["swift_version"]))
    |> Enum.reduce({default_tools_versions, []}, fn manifest, {seen_tools_versions, alternates} ->
      canonical_tools_version = canonical_tools_version(manifest["swift_tools_version"])

      cond do
        is_nil(canonical_tools_version) ->
          {seen_tools_versions, [manifest | alternates]}

        MapSet.member?(seen_tools_versions, canonical_tools_version) ->
          {seen_tools_versions, alternates}

        true ->
          {MapSet.put(seen_tools_versions, canonical_tools_version), [manifest | alternates]}
      end
    end)
    |> elem(1)
    |> Enum.reverse()
  end

  defp canonical_tools_version(nil), do: nil

  defp canonical_tools_version(version) when is_binary(version) do
    case Regex.run(~r/\A(\d+)(?:\.(\d+))?(?:\.(\d+))?\z/, version) do
      [_, major] -> "#{major}.0.0"
      [_, major, minor] -> "#{major}.#{minor}.0"
      [_, major, minor, patch] -> "#{major}.#{minor}.#{patch}"
      _ -> version
    end
  end
end
