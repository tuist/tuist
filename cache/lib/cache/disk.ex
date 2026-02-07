defmodule Cache.Disk do
  @moduledoc """
  Local disk storage backend for Xcode compilation cache (CAS) and module cache artifacts.

  Stores artifacts on the local filesystem with configurable storage directory.
  Uses two-level directory sharding to prevent ext4 directory index overflow.
  """

  alias Cache.Registry.KeyNormalizer

  require Logger

  @doc """
  Checks if a Xcode compilation cache (CAS) artifact exists on disk.

  ## Examples

      iex> Cache.Disk.xcode_cas_exists?("account", "project", "abc123")
      true
  """
  def xcode_cas_exists?(account_handle, project_handle, id) do
    account_handle
    |> xcode_cas_key(project_handle, id)
    |> artifact_path()
    |> File.exists?()
  end

  @doc """
  Writes Xcode compilation cache (CAS) artifact data to disk for given account, project, and artifact ID.

  Accepts either binary data or a file path. For file paths, file is moved
  into place without reading into memory (efficient for large uploads).

  Creates parent directories if they don't exist.

  ## Examples

      iex> Cache.Disk.xcode_cas_put("account", "project", "abc123", <<1, 2, 3>>)
      :ok

      iex> Cache.Disk.xcode_cas_put("account", "project", "abc123", {:file, "/tmp/upload-123"})
      :ok
  """
  def xcode_cas_put(account_handle, project_handle, id, {:file, tmp_path}) do
    path = account_handle |> xcode_cas_key(project_handle, id) |> artifact_path()

    with :ok <- ensure_directory(path) do
      move_file(tmp_path, path)
    end
  end

  def xcode_cas_put(account_handle, project_handle, id, data) when is_binary(data) do
    path = account_handle |> xcode_cas_key(project_handle, id) |> artifact_path()

    with :ok <- ensure_directory(path),
         :ok <- File.write(path, data) do
      :ok
    else
      {:error, reason} = error ->
        Logger.error("Failed to write CAS artifact to #{path}: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Converts a cache key to an absolute file system path.

  ## Examples

      iex> Cache.Disk.artifact_path("account/project/cas/AB/CD/ABCD1234")
      "/var/tuist/cas/account/project/cas/AB/CD/ABCD1234"
  """
  def artifact_path(key) do
    Path.join(storage_dir(), key)
  end

  @doc """
  Constructs a sharded Xcode compilation cache (CAS) key from account handle, project handle, and artifact ID.

  Uses a two-level directory sharding based on the first 4 characters of the artifact ID
  to prevent directory index overflow on ext4 filesystems without `large_dir` enabled.

  ## Examples

      iex> Cache.Disk.xcode_cas_key("account", "project", "ABCD1234")
      "account/project/cas/AB/CD/ABCD1234"
  """
  def xcode_cas_key(account_handle, project_handle, id) do
    {shard1, shard2} = shards_for_id(id)
    "#{account_handle}/#{project_handle}/cas/#{shard1}/#{shard2}/#{id}"
  end

  defp shards_for_id(<<shard1::binary-size(2), shard2::binary-size(2), _rest::binary>>) do
    {shard1, shard2}
  end

  @doc """
  Build the internal X-Accel-Redirect path for a Xcode compilation cache (CAS) artifact.

  The returned path maps to the nginx internal location that aliases the
  physical CAS storage directory.
  """
  def xcode_cas_local_accel_path(account_handle, project_handle, id) do
    "/internal/local/" <> xcode_cas_key(account_handle, project_handle, id)
  end

  @doc """
  Returns the configured storage directory for cache artifacts.

  Defaults to "tmp/cas" if not configured.
  """
  def storage_dir do
    Application.get_env(:cache, :storage_dir)
  end

  @doc """
  Returns local file path for a given Xcode compilation cache (CAS) artifact if the file exists.

  ## Examples

      iex> Cache.Disk.xcode_cas_get_local_path("account", "project", "ABCD1234")
      {:ok, "/var/tuist/cas/account/project/cas/AB/CD/ABCD1234"}
  """
  def xcode_cas_get_local_path(account_handle, project_handle, id) do
    path = account_handle |> xcode_cas_key(project_handle, id) |> artifact_path()

    if File.exists?(path) do
      {:ok, path}
    else
      {:error, :not_found}
    end
  end

  @doc """
  Returns file stat information for a Xcode compilation cache (CAS) artifact.

  ## Examples

      iex> Cache.Disk.xcode_cas_stat("account", "project", "ABCD1234")
      {:ok, %File.Stat{size: 1024, ...}}
  """
  def xcode_cas_stat(account_handle, project_handle, id) do
    account_handle
    |> xcode_cas_key(project_handle, id)
    |> artifact_path()
    |> File.stat()
  end

  @doc """
  Lists all artifact paths on disk.
  """
  def list_artifact_paths(dir \\ storage_dir()) do
    dir
    |> Path.join("**/*")
    |> Path.wildcard(match_dot: true)
    |> Enum.filter(&File.regular?/1)
  end

  @doc """
  Constructs a sharded module cache key from account handle, project handle, category, hash, and name.

  Uses a two-level directory sharding based on the first 4 characters of the hash
  to prevent directory index overflow on ext4 filesystems without `large_dir` enabled.

  ## Examples

      iex> Cache.Disk.module_key("account", "project", "builds", "ABCD1234", "MyModule.xcframework.zip")
      "account/project/module/builds/AB/CD/ABCD1234/MyModule.xcframework.zip"
  """
  def module_key(account_handle, project_handle, category, hash, name) do
    {shard1, shard2} = shards_for_id(hash)
    "#{account_handle}/#{project_handle}/module/#{category}/#{shard1}/#{shard2}/#{hash}/#{name}"
  end

  @doc """
  Checks if a module artifact exists on disk.
  """
  def module_exists?(account_handle, project_handle, category, hash, name) do
    account_handle
    |> module_key(project_handle, category, hash, name)
    |> artifact_path()
    |> File.exists?()
  end

  @doc """
  Writes module artifact data to disk.

  Accepts either binary data or a file path tuple.
  """
  def module_put(account_handle, project_handle, category, hash, name, {:file, tmp_path}) do
    path = account_handle |> module_key(project_handle, category, hash, name) |> artifact_path()

    with :ok <- ensure_directory(path) do
      move_file(tmp_path, path)
    end
  end

  def module_put(account_handle, project_handle, category, hash, name, data) when is_binary(data) do
    path = account_handle |> module_key(project_handle, category, hash, name) |> artifact_path()

    with :ok <- ensure_directory(path),
         :ok <- File.write(path, data) do
      :ok
    else
      {:error, reason} = error ->
        Logger.error("Failed to write module artifact to #{path}: #{inspect(reason)}")
        error
    end
  end

  def module_put_from_parts(account_handle, project_handle, category, hash, name, part_paths) do
    dest_path = account_handle |> module_key(project_handle, category, hash, name) |> artifact_path()

    with :ok <- ensure_directory(dest_path),
         false <- File.exists?(dest_path) do
      tmp_dest = dest_path <> ".tmp.#{:erlang.unique_integer([:positive])}"

      with {:ok, :ok} <- File.open(tmp_dest, [:write, :append, :binary], &copy_parts_to_file(part_paths, &1)),
           :ok <- File.rename(tmp_dest, dest_path) do
        :ok
      else
        {:ok, {:error, reason}} ->
          Logger.error("Failed to assemble artifact to #{dest_path}: #{inspect(reason)}")
          File.rm(tmp_dest)
          {:error, reason}

        {:error, :eexist} ->
          File.rm(tmp_dest)
          {:error, :exists}

        {:error, reason} ->
          Logger.error("Failed to assemble artifact to #{dest_path}: #{inspect(reason)}")
          File.rm(tmp_dest)
          {:error, reason}
      end
    else
      true -> {:error, :exists}
      {:error, reason} -> {:error, reason}
    end
  end

  defp copy_parts_to_file(part_paths, dest_file) do
    Enum.reduce_while(part_paths, :ok, fn part_path, :ok ->
      case File.open(part_path, [:read, :binary, :raw]) do
        {:ok, source} ->
          result = :file.copy(source, dest_file)
          File.close(source)

          case result do
            {:ok, _bytes_copied} -> {:cont, :ok}
            {:error, reason} -> {:halt, {:error, reason}}
          end

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  @doc """
  Returns file stat information for a module artifact.
  """
  def module_stat(account_handle, project_handle, category, hash, name) do
    account_handle
    |> module_key(project_handle, category, hash, name)
    |> artifact_path()
    |> File.stat()
  end

  @doc """
  Build the internal X-Accel-Redirect path for a module artifact.
  """
  def module_local_accel_path(account_handle, project_handle, category, hash, name) do
    "/internal/local/" <> module_key(account_handle, project_handle, category, hash, name)
  end

  @doc """
  Deletes all artifacts for a project from disk.

  Removes the entire project directory, which includes both CAS and module cache artifacts.
  Returns :ok on success, {:error, reason} on failure.
  """
  def delete_project(account_handle, project_handle) do
    path = Path.join(storage_dir(), "#{account_handle}/#{project_handle}")

    case File.rm_rf(path) do
      {:ok, _} -> :ok
      {:error, reason, _} -> {:error, reason}
    end
  end

  @doc """
  Returns disk usage stats for the filesystem that backs the provided path.
  """
  def usage(path) when is_binary(path) do
    expanded_path = Path.expand(path)

    case System.cmd("df", ["-Pk", expanded_path], stderr_to_stdout: true) do
      {output, 0} ->
        parse_df_output(output)

      {output, exit_code} ->
        Logger.warning("df exited with #{exit_code} while inspecting #{expanded_path}: #{String.trim(output)}")

        {:error, :df_failed}
    end
  end

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
        Logger.error("Failed to move CAS artifact to #{target_path}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp parse_df_output(output) do
    lines =
      output
      |> String.trim()
      |> String.split("\n", trim: true)

    case lines do
      [_header, data_line | _] ->
        parse_df_data_line(data_line)

      _ ->
        {:error, :unexpected_df_output}
    end
  end

  defp parse_df_data_line(line) do
    case String.split(line, ~r/\s+/, trim: true) do
      [_filesystem, blocks, used, available, capacity | _] ->
        with {:ok, total_bytes} <- parse_kbytes(blocks),
             {:ok, used_bytes} <- parse_kbytes(used),
             {:ok, available_bytes} <- parse_kbytes(available),
             {:ok, percent_used} <- parse_percent(capacity) do
          {:ok,
           %{
             total_bytes: total_bytes,
             used_bytes: used_bytes,
             available_bytes: available_bytes,
             percent_used: percent_used
           }}
        end

      _ ->
        {:error, :unexpected_df_fields}
    end
  end

  defp parse_kbytes(value) do
    case Integer.parse(value) do
      {int, _} when int >= 0 -> {:ok, int * 1024}
      _ -> {:error, :invalid_number}
    end
  end

  defp parse_percent(value) do
    sanitized = String.trim_trailing(value, "%")

    case Float.parse(sanitized) do
      {number, _} when number >= 0 -> {:ok, number}
      _ -> {:error, :invalid_percent}
    end
  end

  @doc """
  Constructs a sharded Gradle build cache key from account handle, project handle, and cache key hash.

  Uses a two-level directory sharding based on the first 4 characters of the cache key
  to prevent directory index overflow on ext4 filesystems without `large_dir` enabled.

  ## Examples

      iex> Cache.Disk.gradle_key("account", "project", "ABCD1234")
      "account/project/gradle/AB/CD/ABCD1234"
  """
  def gradle_key(account_handle, project_handle, cache_key) do
    {shard1, shard2} = shards_for_id(cache_key)
    "#{account_handle}/#{project_handle}/gradle/#{shard1}/#{shard2}/#{cache_key}"
  end

  @doc """
  Checks if a Gradle build cache artifact exists on disk.

  ## Examples

      iex> Cache.Disk.gradle_exists?("account", "project", "abc123")
      true
  """
  def gradle_exists?(account_handle, project_handle, cache_key) do
    account_handle
    |> gradle_key(project_handle, cache_key)
    |> artifact_path()
    |> File.exists?()
  end

  @doc """
  Writes Gradle build cache artifact data to disk for given account, project, and cache key.

  Accepts either binary data or a file path. For file paths, file is moved
  into place without reading into memory (efficient for large uploads).

  Creates parent directories if they don't exist.

  ## Examples

      iex> Cache.Disk.gradle_put("account", "project", "abc123", <<1, 2, 3>>)
      :ok

      iex> Cache.Disk.gradle_put("account", "project", "abc123", {:file, "/tmp/upload-123"})
      :ok
  """
  def gradle_put(account_handle, project_handle, cache_key, {:file, tmp_path}) do
    path = account_handle |> gradle_key(project_handle, cache_key) |> artifact_path()

    with :ok <- ensure_directory(path) do
      move_file(tmp_path, path)
    end
  end

  def gradle_put(account_handle, project_handle, cache_key, data) when is_binary(data) do
    path = account_handle |> gradle_key(project_handle, cache_key) |> artifact_path()

    with :ok <- ensure_directory(path),
         :ok <- File.write(path, data) do
      :ok
    else
      {:error, reason} = error ->
        Logger.error("Failed to write Gradle artifact to #{path}: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Returns file stat information for a Gradle build cache artifact.

  ## Examples

      iex> Cache.Disk.gradle_stat("account", "project", "ABCD1234")
      {:ok, %File.Stat{size: 1024, ...}}
  """
  def gradle_stat(account_handle, project_handle, cache_key) do
    account_handle
    |> gradle_key(project_handle, cache_key)
    |> artifact_path()
    |> File.stat()
  end

  @doc """
  Build the internal X-Accel-Redirect path for a Gradle build cache artifact.

  The returned path maps to the nginx internal location that aliases the
  physical storage directory.
  """
  def gradle_local_accel_path(account_handle, project_handle, cache_key) do
    "/internal/local/" <> gradle_key(account_handle, project_handle, cache_key)
  end

  # Registry Functions
  # ------------------
  # Registry artifacts use the same storage directory as CAS/module artifacts.
  # The key format matches S3 exactly (no separate sharding) for S3TransferWorker compatibility.

  @doc """
  Constructs a normalized registry key from scope, name, version, and filename.

  The key format matches the server's `package_object_key/2` exactly:
  `registry/swift/{scope}/{name}/{version}/{filename}`

  All components are downcased and the version is normalized.

  ## Examples

      iex> Cache.Disk.registry_key("Apple", "Parser", "v1.2", "source_archive.zip")
      "registry/swift/apple/parser/1.2.0/source_archive.zip"
  """
  def registry_key(scope, name, version, filename) do
    KeyNormalizer.package_object_key(
      %{scope: scope, name: name},
      version: version,
      path: filename
    )
  end

  @doc """
  Checks if a registry artifact exists on disk.

  ## Examples

      iex> Cache.Disk.registry_exists?("apple", "parser", "1.0.0", "source_archive.zip")
      true
  """
  def registry_exists?(scope, name, version, filename) do
    scope
    |> registry_key(name, version, filename)
    |> artifact_path()
    |> File.exists?()
  end

  @doc """
  Writes registry artifact data to disk.

  Accepts either binary data or a file path tuple.
  Creates parent directories if they don't exist.

  ## Examples

      iex> Cache.Disk.registry_put("apple", "parser", "1.0.0", "source_archive.zip", <<1, 2, 3>>)
      :ok

      iex> Cache.Disk.registry_put("apple", "parser", "1.0.0", "source_archive.zip", {:file, "/tmp/upload"})
      :ok
  """
  def registry_put(scope, name, version, filename, {:file, tmp_path}) do
    path = scope |> registry_key(name, version, filename) |> artifact_path()

    with :ok <- ensure_directory(path) do
      move_file(tmp_path, path)
    end
  end

  def registry_put(scope, name, version, filename, data) when is_binary(data) do
    path = scope |> registry_key(name, version, filename) |> artifact_path()

    with :ok <- ensure_directory(path),
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

      iex> Cache.Disk.registry_stat("apple", "parser", "1.0.0", "source_archive.zip")
      {:ok, %File.Stat{size: 1024, ...}}
  """
  def registry_stat(scope, name, version, filename) do
    scope
    |> registry_key(name, version, filename)
    |> artifact_path()
    |> File.stat()
  end

  @doc """
  Build the internal X-Accel-Redirect path for a registry artifact.

  The returned path maps to the nginx internal location that aliases the
  physical storage directory.

  ## Examples

      iex> Cache.Disk.registry_local_accel_path("apple", "parser", "1.0.0", "source_archive.zip")
      "/internal/local/registry/swift/apple/parser/1.0.0/source_archive.zip"
  """
  def registry_local_accel_path(scope, name, version, filename) do
    "/internal/local/" <> registry_key(scope, name, version, filename)
  end
end
