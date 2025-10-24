defmodule Tuist.Cache.Disk do
  @moduledoc """
  Local disk storage backend for CAS (Content Addressable Storage).

  Stores artifacts on the local filesystem with configurable storage directory.
  """

  require Logger

  @doc """
  Checks if an artifact exists on disk.

  ## Examples

      iex> Tuist.Cache.Disk.exists?("account/project/cas/abc123")
      true
  """
  @spec exists?(String.t()) :: boolean()
  def exists?(key) do
    key
    |> artifact_path()
    |> File.exists?()
  end

  @doc """
  Returns a stream for reading an artifact from disk.

  Streams the file in chunks for memory efficiency with large files.

  ## Examples

      iex> Tuist.Cache.Disk.stream("account/project/cas/abc123")
      #Stream<...>
  """
  @spec stream(String.t()) :: Enumerable.t()
  def stream(key) do
    key
    |> artifact_path()
    |> File.stream!([], 64_000)
  end

  @doc """
  Writes data to disk for the given key.

  Creates parent directories if they don't exist.

  ## Examples

      iex> Tuist.Cache.Disk.put("account/project/cas/abc123", <<1, 2, 3>>)
      :ok
  """
  @spec put(String.t(), binary()) :: :ok | {:error, term()}
  def put(key, data) do
    path = artifact_path(key)

    case ensure_directory(path) do
      :ok ->
        case File.write(path, data) do
          :ok ->
            Logger.debug("Wrote CAS artifact to #{path}")
            :ok

          {:error, reason} = error ->
            Logger.error("Failed to write CAS artifact to #{path}: #{inspect(reason)}")
            error
        end

      error ->
        error
    end
  end

  @doc """
  Converts a CAS key to an absolute file system path.

  ## Examples

      iex> Tuist.Cache.Disk.artifact_path("account/project/cas/abc123")
      "/var/tuist/cas/account/project/cas/abc123"
  """
  @spec artifact_path(String.t()) :: Path.t()
  def artifact_path(key) do
    Path.join(storage_dir(), key)
  end

  @doc """
  Returns the configured storage directory for CAS artifacts.

  Defaults to "tmp/cas" if not configured.
  """
  @spec storage_dir() :: Path.t()
  def storage_dir do
    Application.get_env(:tuist, :cas)[:storage_dir] || "tmp/cas"
  end

  defp ensure_directory(file_path) do
    dir = Path.dirname(file_path)

    case File.mkdir_p(dir) do
      :ok -> :ok
      {:error, reason} = error ->
        Logger.error("Failed to create directory #{dir}: #{inspect(reason)}")
        error
    end
  end
end
