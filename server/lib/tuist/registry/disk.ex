defmodule Tuist.Registry.Disk do
  @moduledoc """
  Local-disk caching for registry artifacts on serving pods.

  Each registry-serving pod mounts a region-local PVC at
  `Tuist.Environment.registry_storage_dir/0` and serves cached manifests and
  source archives directly from disk via nginx `x-accel-redirect`. On a miss
  the controller falls back to a presigned S3 URL and the prefetch worker
  populates disk for subsequent reads.
  """

  alias Tuist.Environment
  alias Tuist.Registry.KeyNormalizer

  require Logger

  @local_base_path "/internal/local/"

  def key(scope, name, version, filename) do
    KeyNormalizer.package_object_key(
      %{scope: scope, name: name},
      version: version,
      path: filename
    )
  end

  def exists?(scope, name, version, filename) do
    case storage_dir() do
      nil ->
        false

      _dir ->
        scope
        |> key(name, version, filename)
        |> artifact_path()
        |> File.exists?()
    end
  end

  def stat(scope, name, version, filename) do
    scope
    |> key(name, version, filename)
    |> artifact_path()
    |> File.stat()
  end

  @doc """
  Writes registry artifact data to disk.

  Accepts either binary data or a `{:file, tmp_path}` tuple to atomically move
  a temporary file into place.
  """
  def put(scope, name, version, filename, {:file, tmp_path}) do
    path = scope |> key(name, version, filename) |> artifact_path()

    with :ok <- ensure_directory(path) do
      move_file(tmp_path, path)
    end
  end

  def put(scope, name, version, filename, data) when is_binary(data) do
    path = scope |> key(name, version, filename) |> artifact_path()

    with :ok <- ensure_directory(path),
         :ok <- File.write(path, data) do
      :ok
    else
      {:error, reason} = error ->
        Logger.error("Failed to write registry artifact to #{path}: #{inspect(reason)}")
        error
    end
  end

  def local_accel_path(scope, name, version, filename) do
    @local_base_path <> key(scope, name, version, filename)
  end

  def artifact_path(key) do
    Path.join(storage_dir(), key)
  end

  def storage_dir, do: Environment.registry_storage_dir()

  defp ensure_directory(file_path) do
    dir = Path.dirname(file_path)

    case File.mkdir_p(dir) do
      :ok ->
        :ok

      {:error, reason} = error ->
        Logger.error("Failed to create directory #{dir}: #{inspect(reason)}")
        error
    end
  end

  defp move_file(tmp_path, target_path) do
    with false <- File.exists?(target_path),
         :ok <- File.rename(tmp_path, target_path) do
      :ok
    else
      true ->
        {:error, :exists}

      {:error, reason} ->
        Logger.error("Failed to move artifact to #{target_path}: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
