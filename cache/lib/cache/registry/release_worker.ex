defmodule Cache.Registry.ReleaseWorker do
  @moduledoc """
  Downloads and uploads missing registry artifacts, and updates metadata in S3.
  """

  use Oban.Worker, queue: :registry_release

  alias Cache.Config
  alias Cache.Registry.KeyNormalizer
  alias Cache.Registry.Lock
  alias Cache.Registry.Metadata
  alias Cache.S3

  require Logger

  @github_opts [finch: Cache.Finch, retry: false]

  @alternate_manifest_regex ~r/\APackage@swift-(\d+)(?:\.(\d+))?(?:\.(\d+))?\.swift\z/
  @lock_ttl_seconds 1_800
  @metadata_lock_ttl_seconds 300

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{"scope" => scope, "name" => name, "repository_full_handle" => full_handle, "tag" => tag}
      }) do
    lock_key = {:release, scope, name, KeyNormalizer.normalize_version(tag)}

    case Lock.try_acquire(lock_key, @lock_ttl_seconds) do
      {:ok, :acquired} ->
        try do
          do_sync_release(scope, name, full_handle, tag)
        after
          Lock.release(lock_key)
        end

      {:error, :already_locked} ->
        :ok
    end
  end

  defp do_sync_release(scope, name, full_handle, tag) do
    case Config.registry_github_token() do
      nil ->
        Logger.warning("Registry release sync skipped for #{scope}/#{name}@#{tag}: missing token")
        :ok

      token ->
        normalized_version = KeyNormalizer.normalize_version(tag)

        case Metadata.get_package(scope, name, fresh: true) do
          {:ok, metadata} ->
            releases = Map.get(metadata, "releases", %{})

            if Map.has_key?(releases, normalized_version) do
              :ok
            else
              sync_release(scope, name, full_handle, tag, normalized_version, token)
            end

          {:error, :not_found} ->
            sync_release(scope, name, full_handle, tag, normalized_version, token)
        end
    end
  end

  defp sync_release(scope, name, full_handle, tag, version, token) do
    {:ok, tmp_dir} = Briefly.create(directory: true)
    archive_path = Path.join(tmp_dir, "source_archive.zip")

    with :ok <- fetch_source_archive(full_handle, tag, token, tmp_dir, archive_path),
         {:ok, checksum} <- checksum_for_file(archive_path),
         :ok <- upload_source_archive(scope, name, version, archive_path),
         {:ok, manifests} <- fetch_and_upload_manifests(scope, name, version, full_handle, tag, token) do
      update_metadata_with_release(scope, name, full_handle, version, checksum, manifests)
    else
      {:error, reason} ->
        Logger.warning("Failed to sync release #{scope}/#{name}@#{tag}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp fetch_source_archive(full_handle, tag, token, tmp_dir, archive_path) do
    if has_submodules?(full_handle, tag, token) do
      build_archive_from_clone(full_handle, tag, token, tmp_dir, archive_path)
    else
      build_archive_from_zipball(full_handle, tag, token, tmp_dir, archive_path)
    end
  end

  defp build_archive_from_clone(full_handle, tag, token, tmp_dir, archive_path) do
    with {:ok, source_directory} <- clone_with_submodules(full_handle, tag, token, tmp_dir) do
      zip_directory(source_directory, archive_path)
    end
  end

  defp build_archive_from_zipball(full_handle, tag, token, tmp_dir, archive_path) do
    with :ok <- TuistCommon.GitHub.download_zipball(full_handle, token, tag, archive_path, @github_opts) do
      ensure_archive_without_symlinks(tmp_dir, archive_path)
    end
  end

  # SwiftPM does not correctly handle symlinks when unzipping archives, which breaks
  # packages that contain them (e.g. CLAUDE.md -> AGENTS.md symlinks).
  # This workaround resolves symlinks by repacking the archive before upload.
  # Upstream fix: https://github.com/swiftlang/swift-package-manager/pull/9411
  defp ensure_archive_without_symlinks(tmp_dir, archive_path) do
    case archive_has_symlinks?(archive_path) do
      {:ok, true} -> resolve_symlinks_in_archive(tmp_dir, archive_path)
      {:ok, false} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp has_submodules?(full_handle, tag, token) do
    case TuistCommon.GitHub.get_file_content(full_handle, token, ".gitmodules", tag, @github_opts) do
      {:ok, content} -> content != ""
      {:error, :not_found} -> false
      {:error, _reason} -> false
    end
  end

  defp clone_with_submodules(full_handle, tag, token, tmp_dir) do
    repo_name = full_handle |> String.split("/") |> List.last()
    clone_dest = Path.join(tmp_dir, "#{repo_name}-#{String.replace(tag, "/", "-")}")
    clone_url = "https://#{token}@github.com/#{full_handle}.git"

    case System.cmd(
           "git",
           [
             "-c",
             "url.https://github.com/.insteadOf=git@github.com:",
             "clone",
             "--depth",
             "1",
             "--branch",
             tag,
             clone_url,
             clone_dest
           ],
           stderr_to_stdout: true
         ) do
      {_, 0} ->
        case update_submodules(%{destination: clone_dest, repository_full_handle: full_handle, tag: tag}) do
          :ok ->
            remove_git_metadata(clone_dest)
            {:ok, clone_dest}

          {:error, reason} ->
            {:error, reason}
        end

      {_output, status} ->
        {:error, {:git_clone_failed, status}}
    end
  end

  defp update_submodules(%{destination: destination, repository_full_handle: full_handle, tag: tag}) do
    destination
    |> submodule_paths()
    |> Enum.reduce_while(:ok, fn submodule_path, :ok ->
      case System.cmd(
             "git",
             [
               "-c",
               "url.https://github.com/.insteadOf=git@github.com:",
               "-C",
               destination,
               "submodule",
               "update",
               "--init",
               "--recursive",
               "--depth",
               "1",
               submodule_path
             ],
             stderr_to_stdout: true
           ) do
        {_, 0} ->
          {:cont, :ok}

        {output, status} ->
          if private_submodule_error?(output) do
            Logger.info("Skipping private submodule #{submodule_path} for #{full_handle}@#{tag}")
            {:cont, :ok}
          else
            {:halt, {:error, {:git_submodule_failed, status, output}}}
          end
      end
    end)
  end

  defp submodule_paths(destination) do
    case System.cmd("git", ["-C", destination, "ls-files", "--stage"], stderr_to_stdout: true) do
      {output, 0} ->
        output
        |> String.split("\n", trim: true)
        |> Enum.filter(&String.starts_with?(&1, "160000"))
        |> Enum.map(fn line ->
          case String.split(line, "\t", parts: 2) do
            [_, path] -> String.trim(path)
            _ -> nil
          end
        end)
        |> Enum.reject(&is_nil/1)

      _ ->
        []
    end
  end

  defp private_submodule_error?(output) do
    String.contains?(output, "fatal: could not read Username for")
  end

  defp remove_git_metadata(directory) do
    directory
    |> Path.join("**/.git")
    |> Path.wildcard(match_dot: true)
    |> Enum.each(&File.rm_rf!/1)

    gitmodules_path = Path.join(directory, ".gitmodules")
    if File.exists?(gitmodules_path), do: File.rm(gitmodules_path)
  end

  @doc false
  def zip_directory(directory, archive_path) do
    parent_dir = Path.dirname(directory)
    base_name = Path.basename(directory)

    with :ok <- remove_symlinks_outside_root(directory),
         :ok <- resolve_symlinks(directory) do
      case System.cmd("zip", ["-r", archive_path, base_name], cd: parent_dir) do
        {_, 0} -> :ok
        {output, status} -> {:error, {:zip_failed, status, output}}
      end
    end
  end

  defp resolve_symlinks(directory) do
    case System.cmd("find", [directory, "-type", "l"], stderr_to_stdout: true) do
      {output, 0} ->
        symlink_paths = String.split(output, "\n", trim: true)
        {directory_symlinks, non_directory_symlinks} = classify_symlinks(symlink_paths)

        with :ok <- resolve_non_directory_symlinks(non_directory_symlinks) do
          resolve_directory_symlinks(directory_symlinks)
        end

      {output, status} ->
        {:error, {:find_symlinks_failed, status, output}}
    end
  end

  defp classify_symlinks(symlink_paths) do
    Enum.split_with(symlink_paths, fn path ->
      match?({:ok, %File.Stat{type: :directory}}, File.stat(path))
    end)
  end

  defp resolve_non_directory_symlinks([]), do: :ok

  defp resolve_non_directory_symlinks([symlink_path | rest]) do
    case File.stat(symlink_path) do
      {:ok, %File.Stat{type: :regular}} ->
        content = File.read!(symlink_path)
        File.rm!(symlink_path)
        File.write!(symlink_path, content)

      _ ->
        File.rm(symlink_path)
    end

    resolve_non_directory_symlinks(rest)
  end

  defp resolve_directory_symlinks(directory_symlinks) do
    {cyclic, non_cyclic} =
      Enum.split_with(directory_symlinks, fn path ->
        case File.read_link(path) do
          {:ok, target} ->
            resolved = resolve_symlink_target(path, target)
            symlink_creates_cycle?(Path.expand(path), resolved)

          _ ->
            false
        end
      end)

    Enum.each(cyclic, &remove_cyclic_directory_symlink/1)
    Enum.each(non_cyclic, &resolve_non_cyclic_directory_symlink/1)
  end

  defp remove_cyclic_directory_symlink(symlink_path) do
    {:ok, target} = File.read_link(symlink_path)
    File.rm!(symlink_path)
    Logger.info("Removed recursive directory symlink #{symlink_path} -> #{target}")
  end

  defp resolve_non_cyclic_directory_symlink(symlink_path) do
    {:ok, target} = File.read_link(symlink_path)
    resolved_target = resolve_symlink_target(symlink_path, target)
    File.rm!(symlink_path)
    File.cp_r!(resolved_target, symlink_path)
  end

  defp symlink_creates_cycle?(symlink_path, resolved_target) do
    symlink_path == resolved_target or String.starts_with?(symlink_path, resolved_target <> "/")
  end

  defp resolve_symlinks_in_archive(tmp_dir, archive_path) do
    extract_dir = Path.join(tmp_dir, "extract")
    Logger.info("Resolving symlinks in source archive at #{archive_path}")

    with :ok <- ensure_extract_directory(extract_dir),
         :ok <- unzip_archive(archive_path, extract_dir),
         {:ok, top_level_directory} <- extract_archive_root_directory(extract_dir),
         :ok <- remove_archive(archive_path) do
      zip_directory(top_level_directory, archive_path)
    end
  end

  defp ensure_extract_directory(extract_dir) do
    case File.mkdir_p(extract_dir) do
      :ok -> :ok
      {:error, reason} -> {:error, {:create_extract_directory_failed, reason}}
    end
  end

  defp unzip_archive(archive_path, extract_dir) do
    case System.cmd("unzip", [archive_path, "-d", extract_dir], stderr_to_stdout: true) do
      {_, 0} -> :ok
      {output, status} -> {:error, {:unzip_resolve_symlinks_failed, status, output}}
    end
  end

  defp extract_archive_root_directory(extract_dir) do
    case File.ls(extract_dir) do
      {:ok, [top_level]} ->
        top_level_directory = Path.join(extract_dir, top_level)

        case File.lstat(top_level_directory) do
          {:ok, %File.Stat{type: :directory}} -> {:ok, top_level_directory}
          {:ok, _} -> {:error, {:invalid_archive_layout, :top_level_not_directory, top_level}}
          {:error, reason} -> {:error, {:lstat_top_level_directory_failed, reason}}
        end

      {:ok, entries} ->
        {:error, {:invalid_archive_layout, :expected_single_top_level, entries}}

      {:error, reason} ->
        {:error, {:list_extract_directory_failed, reason}}
    end
  end

  defp remove_archive(archive_path) do
    case File.rm(archive_path) do
      :ok -> :ok
      {:error, reason} -> {:error, {:remove_original_archive_failed, reason}}
    end
  end

  defp remove_symlinks_outside_root(root_directory) do
    expanded_root_directory = Path.expand(root_directory)
    prune_symlinks_outside_root([expanded_root_directory], expanded_root_directory)
  end

  defp prune_symlinks_outside_root([], _root_directory), do: :ok

  defp prune_symlinks_outside_root([path | rest], root_directory) do
    case File.lstat(path) do
      {:ok, stat} ->
        prune_symlink_path(stat, path, rest, root_directory)

      {:error, reason} ->
        {:error, {:path_lstat_failed, path, reason}}
    end
  end

  defp prune_symlink_path(%File.Stat{type: :symlink}, path, rest, root_directory) do
    case File.read_link(path) do
      {:ok, target} ->
        case ensure_symlink_target_within_root(path, target, root_directory) do
          :ok ->
            prune_symlinks_outside_root(rest, root_directory)

          {:symlink_outside_root, _target} ->
            Logger.warning("Removing symlink #{path} -> #{target} because it points outside #{root_directory}")
            File.rm!(path)
            prune_symlinks_outside_root(rest, root_directory)
        end

      {:error, reason} ->
        {:error, {:symlink_read_failed, path, reason}}
    end
  end

  defp prune_symlink_path(%File.Stat{type: :directory}, path, rest, root_directory) do
    case File.ls(path) do
      {:ok, entries} ->
        next_paths = Enum.map(entries, &Path.join(path, &1))
        prune_symlinks_outside_root(next_paths ++ rest, root_directory)

      {:error, reason} ->
        {:error, {:directory_list_failed, path, reason}}
    end
  end

  defp prune_symlink_path(_stat, _path, rest, root_directory) do
    prune_symlinks_outside_root(rest, root_directory)
  end

  defp ensure_symlink_target_within_root(path, target, root_directory) do
    resolved_target = resolve_symlink_target(path, target)

    if path_within_root?(resolved_target, root_directory) do
      :ok
    else
      {:symlink_outside_root, target}
    end
  end

  defp resolve_symlink_target(link_path, target) do
    if Path.type(target) == :absolute do
      Path.expand(target)
    else
      link_path
      |> Path.dirname()
      |> Path.join(target)
      |> Path.expand()
    end
  end

  defp path_within_root?(path, root_directory) do
    path == root_directory or String.starts_with?(path, root_directory <> "/")
  end

  defp archive_has_symlinks?(archive_path) do
    case System.cmd("unzip", ["-Z", archive_path], stderr_to_stdout: true) do
      {output, 0} ->
        has_symlinks =
          output
          |> String.split("\n")
          |> Enum.any?(&String.starts_with?(&1, "l"))

        {:ok, has_symlinks}

      {output, status} ->
        {:error, {:invalid_archive, status, output}}
    end
  end

  defp upload_source_archive(scope, name, version, archive_path) do
    key = KeyNormalizer.package_object_key(%{scope: scope, name: name}, version: version, path: "source_archive.zip")
    S3.upload_file(key, archive_path, type: :registry, content_type: "application/zip")
  end

  defp fetch_and_upload_manifests(scope, name, version, full_handle, tag, token) do
    with {:ok, contents} <- TuistCommon.GitHub.list_repository_contents(full_handle, token, tag, @github_opts) do
      manifests =
        contents
        |> Enum.map(&Map.get(&1, "path"))
        |> Enum.filter(&manifest_path?/1)
        |> Enum.map(fn path ->
          filename = Path.basename(path)
          swift_version = manifest_swift_version(filename)

          with {:ok, content} <- TuistCommon.GitHub.get_file_content(full_handle, token, path, tag, @github_opts),
               :ok <- upload_manifest(scope, name, version, filename, content) do
            %{
              "swift_version" => swift_version,
              "swift_tools_version" => swift_tools_version(content)
            }
          else
            {:error, reason} ->
              Logger.warning("Failed to fetch manifest #{path} for #{scope}/#{name}@#{tag}: #{inspect(reason)}")
              nil
          end
        end)
        |> Enum.reject(&is_nil/1)

      {:ok, manifests}
    end
  end

  defp update_metadata_with_release(scope, name, full_handle, version, checksum, manifests) do
    lock_key = {:package, scope, name}

    case Lock.try_acquire(lock_key, @metadata_lock_ttl_seconds) do
      {:ok, :acquired} ->
        try do
          with {:ok, metadata} <- get_or_create_metadata(scope, name, full_handle) do
            updated_metadata = build_updated_metadata(metadata, scope, name, full_handle, version, checksum, manifests)
            Metadata.put_package(scope, name, updated_metadata)
          end
        after
          Lock.release(lock_key)
        end

      {:error, :already_locked} ->
        Logger.info("Metadata update skipped for #{scope}/#{name}@#{version}: lock held by another node")
        :ok
    end
  end

  defp get_or_create_metadata(scope, name, full_handle) do
    case Metadata.get_package(scope, name, fresh: true) do
      {:ok, metadata} ->
        {:ok, metadata}

      {:error, :not_found} ->
        {:ok, %{"scope" => scope, "name" => name, "repository_full_handle" => full_handle, "releases" => %{}}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_updated_metadata(metadata, scope, name, full_handle, version, checksum, manifests) do
    metadata
    |> Map.put_new("scope", scope)
    |> Map.put_new("name", name)
    |> Map.put("repository_full_handle", full_handle)
    |> Map.put("updated_at", DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601())
    |> Map.update(
      "releases",
      %{version => %{"checksum" => checksum, "manifests" => manifests}},
      fn releases ->
        Map.put(releases || %{}, version, %{
          "checksum" => checksum,
          "manifests" => manifests
        })
      end
    )
  end

  defp upload_manifest(scope, name, version, filename, content) do
    key = KeyNormalizer.package_object_key(%{scope: scope, name: name}, version: version, path: filename)
    S3.upload_content(key, content, type: :registry, content_type: "text/x-swift")
  end

  defp manifest_path?("Package.swift"), do: true
  defp manifest_path?(path) when is_binary(path), do: Regex.match?(@alternate_manifest_regex, Path.basename(path))
  defp manifest_path?(_), do: false

  defp manifest_swift_version("Package.swift"), do: nil

  defp manifest_swift_version(filename) do
    case Regex.run(@alternate_manifest_regex, filename) do
      [_, major] -> major
      [_, major, minor] -> "#{major}.#{minor}"
      [_, major, minor, patch] -> "#{major}.#{minor}.#{patch}"
      _ -> nil
    end
  end

  defp swift_tools_version(content) do
    case Regex.run(~r/^\/\/ swift-tools-version:\s?(\d+)(?:\.(\d+))?(?:\.(\d+))?/, content) do
      [_, major] -> major
      [_, major, minor] -> "#{major}.#{minor}"
      [_, major, minor, patch] -> "#{major}.#{minor}.#{patch}"
      _ -> nil
    end
  end

  defp checksum_for_file(path) do
    hash =
      path
      |> File.stream!(2048, [])
      |> Enum.reduce(:crypto.hash_init(:sha256), fn chunk, acc ->
        :crypto.hash_update(acc, chunk)
      end)
      |> :crypto.hash_final()
      |> Base.encode16(case: :lower)

    {:ok, hash}
  end
end
