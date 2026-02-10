defmodule Cache.Registry.Disk do
  @moduledoc """
  Local disk storage backend for Swift package registry artifacts.

  Stores registry artifacts on the local filesystem with normalized keys
  that match the server's S3 storage format for proper synchronization.
  """

  alias Cache.Disk
  alias Cache.Registry.KeyNormalizer

  require Logger

  @doc """
  Constructs a normalized registry key from scope, name, version, and filename.

  The key format matches the server's `package_object_key/2` exactly:
  `registry/swift/{scope}/{name}/{version}/{filename}`

  All components are downcased and the version is normalized.

  ## Examples

      iex> Cache.Registry.Disk.key("Apple", "Parser", "v1.2", "source_archive.zip")
      "registry/swift/apple/parser/1.2.0/source_archive.zip"
  """
  @spec key(binary(), binary(), binary(), binary()) :: binary()
  def key(scope, name, version, filename) do
    KeyNormalizer.package_object_key(
      %{scope: scope, name: name},
      version: version,
      path: filename
    )
  end

  @doc """
  Checks if a registry artifact exists on disk.

  ## Examples

      iex> Cache.Registry.Disk.exists?("apple", "parser", "1.0.0", "source_archive.zip")
      true
  """
  @spec exists?(binary(), binary(), binary(), binary()) :: boolean()
  def exists?(scope, name, version, filename) do
    scope
    |> key(name, version, filename)
    |> Disk.artifact_path()
    |> File.exists?()
  end

  @doc """
  Writes registry artifact data to disk.

  Accepts either binary data or a file path tuple.
  Creates parent directories if they don't exist.

  ## Examples

      iex> Cache.Registry.Disk.put("apple", "parser", "1.0.0", "source_archive.zip", <<1, 2, 3>>)
      :ok

      iex> Cache.Registry.Disk.put("apple", "parser", "1.0.0", "source_archive.zip", {:file, "/tmp/upload"})
      :ok
  """
  @spec put(binary(), binary(), binary(), binary(), binary() | {:file, binary()}) :: :ok | {:error, atom()}
  def put(scope, name, version, filename, {:file, tmp_path}) do
    path = scope |> key(name, version, filename) |> Disk.artifact_path()

    with :ok <- Disk.ensure_directory(path) do
      Disk.move_file(tmp_path, path)
    end
  end

  def put(scope, name, version, filename, data) when is_binary(data) do
    path = scope |> key(name, version, filename) |> Disk.artifact_path()

    with :ok <- Disk.ensure_directory(path),
         :ok <- File.write(path, data) do
      :ok
    else
      {:error, reason} = error ->
        Logger.error("Failed to write registry artifact to #{path}: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Returns file stat information for a registry artifact.

  ## Examples

      iex> Cache.Registry.Disk.stat("apple", "parser", "1.0.0", "source_archive.zip")
      {:ok, %File.Stat{size: 1024, ...}}
  """
  @spec stat(binary(), binary(), binary(), binary()) :: {:ok, File.Stat.t()} | {:error, atom()}
  def stat(scope, name, version, filename) do
    scope
    |> key(name, version, filename)
    |> Disk.artifact_path()
    |> File.stat()
  end

  @doc """
  Build the internal X-Accel-Redirect path for a registry artifact.

  The returned path maps to the nginx internal location that aliases the
  physical storage directory.

  ## Examples

      iex> Cache.Registry.Disk.local_accel_path("apple", "parser", "1.0.0", "source_archive.zip")
      "/internal/local/registry/swift/apple/parser/1.0.0/source_archive.zip"
  """
  @spec local_accel_path(binary(), binary(), binary(), binary()) :: binary()
  def local_accel_path(scope, name, version, filename) do
    "/internal/local/" <> key(scope, name, version, filename)
  end
end
