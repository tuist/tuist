defmodule Tuist.Registry.KeyNormalizer do
  @moduledoc """
  Normalizes registry package keys (scope, name, version) for consistent S3
  storage and local disk paths.
  """

  @source_tag_regex ~r/^v?\d+\.\d+(\.\d+)?(-[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?(\+[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?$/
  @storage_version_regex ~r/^\d+\.\d+(\.\d+)?(-[0-9A-Za-z-]+(\+[0-9A-Za-z-]+)*)?(\+[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?$/

  def normalize_scope(scope) when is_binary(scope) do
    String.downcase(scope)
  end

  def normalize_name(name) when is_binary(name) do
    name |> String.replace(".", "_") |> String.downcase()
  end

  def normalize_scope_name(scope, name) when is_binary(scope) and is_binary(name) do
    {normalize_scope(scope), normalize_name(name)}
  end

  def normalize_version(version) when is_binary(version) do
    version = String.trim_leading(version, "v")

    case String.split(version, "-") do
      [base, prerelease] ->
        prerelease_with_plus = String.replace(prerelease, ".", "+")
        base = add_trailing_semantic_version_zeros(base)
        "#{base}-#{prerelease_with_plus}"

      _ ->
        add_trailing_semantic_version_zeros(version)
    end
  end

  def valid_source_tag?(version) when is_binary(version) do
    Regex.match?(@source_tag_regex, version)
  end

  def valid_storage_version?(version) when is_binary(version) do
    Regex.match?(@storage_version_regex, version)
  end

  defp add_trailing_semantic_version_zeros(version) do
    case String.split(version, ".") do
      [major] ->
        "#{strip_leading_zeros(major)}.0.0"

      [major, minor] ->
        "#{strip_leading_zeros(major)}.#{strip_leading_zeros(minor)}.0"

      [major, minor, patch] ->
        "#{strip_leading_zeros(major)}.#{strip_leading_zeros(minor)}.#{strip_leading_zeros(patch)}"

      _ ->
        version
    end
  end

  defp strip_leading_zeros(component) do
    case Integer.parse(component) do
      {int, ""} -> Integer.to_string(int)
      _ -> component
    end
  end

  def package_object_key(%{scope: scope, name: name}, opts \\ []) do
    version = Keyword.get(opts, :version)
    path = Keyword.get(opts, :path)

    object_key = "registry/swift/#{normalize_scope(scope)}/#{normalize_name(name)}"

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
