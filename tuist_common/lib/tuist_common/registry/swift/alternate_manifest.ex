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
end
