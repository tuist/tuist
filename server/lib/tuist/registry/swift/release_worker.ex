defmodule Tuist.Registry.Swift.ReleaseWorker do
  @moduledoc """
  Downloads a single Swift package release from GitHub and writes the
  source archive, manifests, and metadata into the registry S3 bucket.

  Enqueued by `Tuist.Registry.Swift.SyncWorker`. Runs in the
  swift-registry-sync pod (`TUIST_MODE=swift_registry_sync`).
  """

  use Oban.Worker, queue: :swift_registry_release

  alias Tuist.Registry
  alias Tuist.Registry.S3
  alias Tuist.Registry.Swift.Lock
  alias Tuist.Registry.Swift.Metadata
  alias TuistCommon.Git.Authentication, as: GitAuthentication
  alias TuistCommon.Registry.Swift.AlternateManifest
  alias TuistCommon.Registry.Swift.KeyNormalizer

  require Logger

  @github_opts [finch: Tuist.Finch, retry: false]

  @lock_ttl_seconds 1_800
  @metadata_lock_ttl_seconds 300
  @metadata_lock_max_attempts 5
  @metadata_lock_backoff_ms 200
  @metadata_lock_snooze_seconds 30

  # Same bounds as `Tuist.Registry.Swift.SyncWorker`: GitHub's primary quota
  # window is an hour, and a reset that has already elapsed must not turn into
  # an immediate re-run against a budget that has not recovered.
  @min_snooze_seconds 60
  @max_snooze_seconds 3_600
  @default_snooze_seconds 600

  @release_deferred_event [:tuist, :registry, :swift, :release, :deferred]

  @doc false
  def release_deferred_event_name, do: @release_deferred_event

  # Symlinks nested inside these code-signed bundles are part of the bundle's
  # sealed layout (e.g. a Mac Catalyst framework's `Versions/Current -> A` and
  # the `Binary`/`Resources` links). Code signing records them as symlinks in
  # `_CodeSignature/CodeResources`, so flattening them into real copies
  # invalidates the signature ("a sealed resource is missing or invalid"). They
  # always live well below the package root, so the SwiftPM root-level symlink
  # extraction bug that `resolve_symlinks/1` works around
  # (https://github.com/swiftlang/swift-package-manager/pull/9411) does not
  # apply to them, and they are safe to keep as symlinks in the archive.
  @signed_bundle_extensions ~w(.xcframework .framework .app .appex .bundle .dSYM .plugin .systemextension .xpc)

  @skippable_submodule_failure_markers [
    "no url found for submodule path",
    "transport 'file' not allowed",
    "url using bad/illegal format or missing url",
    "repository not found",
    "does not appear to be a git repository",
    "the requested url returned error: 404",
    "write access to repository not granted",
    "fatal: could not read username for",
    "not our ref",
    "did not contain",
    "unable to find current revision in submodule path",
    "reference is not a tree",
    "needed a single revision"
  ]

  @transient_submodule_failure_markers [
    "rate limit",
    "too many requests",
    "temporarily blocked",
    "try again later"
  ]

  # Git renders an HTTP failure as the bare status line and only relays the
  # host's explanation when the error body is `text/plain`, so a throttled host
  # serving HTML or an empty body matches none of the prose markers above.
  # Matching the status itself is what covers those.
  @transient_http_statuses ~w(429 502 503 504)

  # GitHub answers a throttled clone with the same 403 it uses for a repository
  # the token cannot see, so a 403 from it says nothing durable. Elsewhere a 403
  # is an access-control decision that will not change on retry, which is how
  # Gerrit hosts such as review.mlplatform.org refuse anonymous clones. A
  # private GitHub repository the token cannot see answers 404, which is already
  # classified permanent, so scoping this away from GitHub loses no coverage.
  @ambiguous_forbidden_hosts ["github.com"]

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{"scope" => scope, "name" => name, "repository_full_handle" => full_handle, "tag" => tag} = args
      }) do
    lock_key = {:release, scope, name, KeyNormalizer.normalize_version(tag)}

    case Lock.try_acquire(lock_key, @lock_ttl_seconds) do
      {:ok, :acquired} ->
        try do
          do_sync_release(scope, name, full_handle, tag, resync_opts(args))
        after
          Lock.release(lock_key)
        end

      {:error, :already_locked} ->
        :ok
    end
  end

  defp resync_opts(args) do
    %{
      force?: Map.get(args, "force", false),
      allow_checksum_change?: Map.get(args, "allow_checksum_change", false),
      published_checksum: nil
    }
  end

  defp do_sync_release(scope, name, full_handle, tag, opts) do
    case Registry.swift_registry_github_token() do
      nil ->
        # A configured mirror whose App momentarily cannot issue a token would
        # otherwise report a clean run for a release it never attempted, which
        # is exactly the silent loss of coverage this path is meant to avoid.
        if Registry.swift_registry_github_credentials_configured?() do
          Logger.error("Deferring registry release #{scope}/#{name}@#{tag}: no GitHub credential could be resolved")

          :telemetry.execute(@release_deferred_event, %{releases: 1}, %{reason: :missing_credential})

          {:snooze, @default_snooze_seconds}
        else
          Logger.warning("Registry release sync skipped for #{scope}/#{name}@#{tag}: missing token")
          :ok
        end

      token ->
        normalized_version = KeyNormalizer.normalize_version(tag)

        case Metadata.get_package(scope, name, fresh: true) do
          {:ok, metadata} ->
            releases = Map.get(metadata, "releases", %{})
            skipped_releases = Map.get(metadata, "skipped_releases", %{})

            if not opts.force? and
                 (Map.has_key?(releases, normalized_version) or
                    Metadata.verified_skip?(Map.get(skipped_releases, normalized_version))) do
              :ok
            else
              opts = %{opts | published_checksum: published_checksum(releases, normalized_version)}
              sync_release(scope, name, full_handle, tag, normalized_version, token, opts)
            end

          {:error, :not_found} ->
            sync_release(scope, name, full_handle, tag, normalized_version, token, opts)
        end
    end
  end

  defp published_checksum(releases, version) do
    case Map.get(releases, version) do
      %{"checksum" => checksum} when is_binary(checksum) -> checksum
      _release -> nil
    end
  end

  defp sync_release(scope, name, full_handle, tag, version, token, opts) do
    {:ok, tmp_dir} = Briefly.create(directory: true)
    archive_path = Path.join(tmp_dir, "source_archive.zip")

    with {:ok, manifest_payloads} <- fetch_manifests(full_handle, tag, token),
         :ok <- fetch_source_archive(full_handle, tag, token, tmp_dir, archive_path),
         {:ok, checksum} <- checksum_for_file(archive_path),
         :ok <- ensure_checksum_change_allowed(scope, name, version, checksum, opts),
         :ok <- upload_source_archive(scope, name, version, archive_path, checksum),
         :ok <- verify_stored_archive(scope, name, version, checksum),
         {:ok, manifests} <- upload_manifests(scope, name, version, manifest_payloads) do
      update_metadata_with_release(scope, name, full_handle, version, checksum, manifests)
    else
      {:error, {:checksum_change_refused, details} = reason} ->
        Logger.warning(
          "Refusing to republish #{scope}/#{name}@#{version}: rebuilding produced #{details.rebuilt} " <>
            "but #{details.published} is already published. Re-run with allow_checksum_change to override."
        )

        {:discard, reason}

      {:error, reason} ->
        case maybe_skip_release(scope, name, full_handle, version, reason) do
          :ok ->
            :ok

          # Every deferral path logs its own reason before returning, so this
          # only forwards the delay.
          {:snooze, seconds} ->
            {:snooze, seconds}

          {:discard, discard_reason} ->
            {:discard, discard_reason}

          :not_skipped ->
            Logger.warning("Failed to sync release #{scope}/#{name}@#{tag}: #{inspect(reason)}")
            {:error, reason}

          {:error, skip_reason} ->
            Logger.warning("Failed to record skipped release #{scope}/#{name}@#{tag}: #{inspect(skip_reason)}")

            Logger.warning("Failed to sync release #{scope}/#{name}@#{tag}: #{inspect(reason)}")
            {:error, reason}
        end
    end
  end

  defp fetch_source_archive(full_handle, tag, token, tmp_dir, archive_path) do
    with {:ok, submodule_paths} <- fetch_submodule_paths(full_handle, tag, token) do
      case submodule_paths do
        [] ->
          build_archive_from_zipball(full_handle, tag, token, tmp_dir, archive_path)

        _submodule_paths ->
          build_archive_from_clone(full_handle, tag, token, tmp_dir, archive_path)
      end
    end
  end

  defp build_archive_from_clone(full_handle, tag, token, tmp_dir, archive_path) do
    with {:ok, source_directory} <- clone_with_submodules(full_handle, tag, token, tmp_dir),
         :ok <- zip_directory(source_directory, archive_path) do
      verify_archive_directories(archive_path)
    end
  end

  defp build_archive_from_zipball(full_handle, tag, token, tmp_dir, archive_path) do
    with :ok <-
           TuistCommon.GitHub.download_zipball(
             full_handle,
             token,
             tag,
             archive_path,
             @github_opts
           ) do
      normalize_archive(tmp_dir, archive_path)
    end
  end

  # SwiftPM does not correctly handle symlinks when unzipping archives, which breaks
  # packages that contain them (e.g. CLAUDE.md -> AGENTS.md symlinks).
  # This workaround resolves symlinks by repacking the archive before upload.
  # Upstream fix: https://github.com/swiftlang/swift-package-manager/pull/9411
  # A single listing answers both questions asked of a downloaded archive, so
  # the archive it passes through untouched is inspected exactly once. An
  # archive whose directories are already unreadable is rejected rather than
  # repacked: extracting it lays the same modes down on disk and `zip` records
  # them again, so repacking cannot repair it.
  defp normalize_archive(tmp_dir, archive_path) do
    with {:ok, listing} <- inspect_archive(archive_path),
         :ok <- reject_unreadable_directories(listing) do
      if listing.symlinks?, do: repackage_archive(tmp_dir, archive_path), else: :ok
    end
  end

  defp fetch_submodule_paths(full_handle, tag, token) do
    case TuistCommon.GitHub.get_file_content(full_handle, token, ".gitmodules", tag, @github_opts) do
      {:ok, content} -> {:ok, parse_gitmodules_paths(content)}
      {:error, :not_found} -> {:ok, []}
      {:error, reason} -> {:error, {:gitmodules_fetch_failed, reason}}
    end
  end

  defp parse_gitmodules_paths(content) do
    ~r/^\s*path\s*=\s*(.+?)\s*$/m
    |> Regex.scan(content, capture: :all_but_first)
    |> Enum.map(fn [path] -> String.trim(path) end)
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(&normalize_package_relative_path/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp clone_with_submodules(full_handle, tag, token, tmp_dir) when is_binary(token) and token != "" do
    repo_name = full_handle |> String.split("/") |> List.last()
    clone_dest = Path.join(tmp_dir, "#{repo_name}-#{String.replace(tag, "/", "-")}")

    GitAuthentication.with_github_token(tmp_dir, token, fn git_credentials ->
      case System.cmd(
             "git",
             GitAuthentication.config_args(git_credentials) ++
               [
                 "clone",
                 "--depth",
                 "1",
                 "--branch",
                 tag,
                 "https://github.com/#{full_handle}.git",
                 clone_dest
               ],
             stderr_to_stdout: true,
             env: GitAuthentication.command_env(git_credentials)
           ) do
        {_, 0} ->
          case update_submodules(%{
                 destination: clone_dest,
                 repository_full_handle: full_handle,
                 tag: tag,
                 git_credentials: git_credentials
               }) do
            :ok ->
              remove_git_metadata(clone_dest)
              {:ok, clone_dest}

            {:error, reason} ->
              {:error, reason}
          end

        {_output, status} ->
          {:error, {:git_clone_failed, status}}
      end
    end)
  end

  defp clone_with_submodules(full_handle, tag, _token, tmp_dir) do
    repo_name = full_handle |> String.split("/") |> List.last()
    clone_dest = Path.join(tmp_dir, "#{repo_name}-#{String.replace(tag, "/", "-")}")

    case System.cmd(
           "git",
           GitAuthentication.config_args(nil) ++
             [
               "clone",
               "--depth",
               "1",
               "--branch",
               tag,
               "https://github.com/#{full_handle}.git",
               clone_dest
             ],
           stderr_to_stdout: true,
           env: GitAuthentication.command_env(nil)
         ) do
      {_, 0} ->
        case update_submodules(%{
               destination: clone_dest,
               repository_full_handle: full_handle,
               tag: tag
             }) do
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

  @doc false
  def update_submodules(%{destination: destination, repository_full_handle: full_handle, tag: tag} = opts) do
    context = %{
      repository_full_handle: full_handle,
      tag: tag,
      git_credentials: Map.get(opts, :git_credentials)
    }

    update_submodules_in(destination, nil, context)
  end

  # `git submodule update --recursive` reports a failure anywhere in the tree as
  # a failure of the top-level submodule it was reached through, so an
  # unreachable third-party dependency nested several levels down is
  # indistinguishable from the package's own submodule being unreachable.
  # Descending one level at a time attributes every failure to the exact path
  # that produced it, so a skippable failure drops only that path instead of the
  # required subtree that happened to lead to it.
  defp update_submodules_in(repository_directory, path_prefix, context) do
    with {:ok, submodule_paths} <- submodule_paths(repository_directory, path_prefix) do
      Enum.reduce_while(submodule_paths, :ok, fn submodule_path, :ok ->
        update_submodule_tree(repository_directory, submodule_path, path_prefix, context)
      end)
    end
  end

  defp update_submodule_tree(repository_directory, submodule_path, path_prefix, context) do
    full_path = join_submodule_path(path_prefix, submodule_path)
    submodule_directory = Path.join(repository_directory, submodule_path)

    case update_submodule(repository_directory, submodule_path, context.git_credentials) do
      :ok ->
        descend_into_submodule(submodule_directory, full_path, context)

      {:skip, output} ->
        handle_skipped_submodule(repository_directory, submodule_path, full_path, context, output)

      {:throttled, status, output} ->
        {:halt, {:error, {:git_submodule_update_throttled, full_path, status, output}}}

      {:failed, status, output} ->
        {:halt, {:error, {:git_submodule_update_failed, full_path, status, output}}}
    end
  end

  defp descend_into_submodule(submodule_directory, full_path, context) do
    if submodule_checkout?(submodule_directory) do
      case update_submodules_in(submodule_directory, full_path, context) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    else
      {:cont, :ok}
    end
  end

  # A zero exit status does not by itself mean the submodule was populated: a
  # `.gitmodules` declaring `update = none` makes git report success while
  # leaving the empty directory the superproject checkout created. Listing that
  # directory finds the *superproject*, whose repository discovery walks up from
  # the gitlink and renders the gitlink itself as the relative path `./`, so
  # descending would re-enter the same directory without ever reaching a fixed
  # point. Requiring a checkout of its own restores what `--recursive` did here,
  # which was to skip the submodule and move on.
  defp submodule_checkout?(directory), do: File.exists?(Path.join(directory, ".git"))

  defp join_submodule_path(nil, submodule_path), do: submodule_path
  defp join_submodule_path(path_prefix, submodule_path), do: "#{path_prefix}/#{submodule_path}"

  defp handle_skipped_submodule(repository_directory, submodule_path, full_path, context, output) do
    case remove_failed_submodule_contents(repository_directory, submodule_path) do
      :ok ->
        Logger.warning(
          "Skipping submodule #{full_path} for #{context.repository_full_handle}@#{context.tag} after permanent git submodule update failure: #{output}"
        )

        {:cont, :ok}

      {:error, reason} ->
        {:halt, {:error, reason}}
    end
  end

  defp update_submodule(repository_directory, submodule_path, git_credentials) do
    case System.cmd(
           "git",
           GitAuthentication.config_args(git_credentials) ++
             [
               "-C",
               repository_directory,
               "submodule",
               "update",
               "--init",
               "--depth",
               "1",
               "--",
               submodule_path
             ],
           stderr_to_stdout: true,
           env: GitAuthentication.command_env(git_credentials)
         ) do
      {_, 0} ->
        :ok

      {output, status} ->
        output =
          output
          |> String.trim()
          |> case do
            "" -> "(no output)"
            trimmed -> trimmed
          end

        case classify_submodule_failure(output) do
          :permanent -> {:skip, output}
          :transient -> {:throttled, status, output}
          :unknown -> {:failed, status, output}
        end
    end
  end

  @doc false
  def skippable_submodule_failure?(output), do: classify_submodule_failure(output) == :permanent

  # Skipping is permanent: the release ships an archive that no longer contains
  # the submodule, so a host that is merely throttling us must not be read as one
  # that will never serve the repository. GitHub answers a throttled clone with
  # the same 403 it uses for a repository the token cannot see, and only the
  # accompanying message tells the two apart. Throttling is kept distinct from an
  # unclassified failure rather than folded into it, so the release can be
  # deferred instead of retried against a host that has just asked us to slow
  # down.
  defp classify_submodule_failure(output) do
    downcased_output = String.downcase(output)

    cond do
      Enum.any?(@transient_submodule_failure_markers, &String.contains?(downcased_output, &1)) ->
        :transient

      http_status(downcased_output) in @transient_http_statuses ->
        :transient

      Enum.any?(@skippable_submodule_failure_markers, &String.contains?(downcased_output, &1)) ->
        :permanent

      forbidden_by_policy?(downcased_output) ->
        :permanent

      true ->
        :unknown
    end
  end

  defp http_status(downcased_output) do
    case Regex.run(~r/returned error: (\d{3})/, downcased_output, capture: :all_but_first) do
      [status] -> status
      _ -> nil
    end
  end

  # Git reports the refused URL and its status on one line, so the host that
  # denied us is read from that line rather than from anywhere else in the
  # output, which may mention several remotes.
  defp forbidden_by_policy?(downcased_output) do
    case Regex.run(~r/unable to access '([^']+)'[^\n]*returned error: 403/, downcased_output, capture: :all_but_first) do
      [url] -> not ambiguous_forbidden_host?(url)
      _ -> false
    end
  end

  defp ambiguous_forbidden_host?(url) do
    host = URI.parse(url).host || ""

    Enum.any?(@ambiguous_forbidden_hosts, &(host == &1 or String.ends_with?(host, "." <> &1)))
  end

  defp remove_failed_submodule_contents(repository_directory, submodule_path) do
    case File.rm_rf(Path.join(repository_directory, submodule_path)) do
      {:ok, _removed_paths} -> :ok
      {:error, reason, path} -> {:error, {:remove_failed_submodule_contents_failed, path, reason}}
    end
  end

  # `-z` is what keeps the path usable rather than merely readable: without it
  # git C-quotes any path containing non-ASCII bytes, quotes, backslashes or
  # control characters, and the quoted rendering (`"caf\303\251"`) is handed
  # straight back to git as a pathspec that matches nothing and to
  # `File.rm_rf/1`, where a skip would delete nothing. NUL termination also
  # means a path may be taken verbatim, since trimming would corrupt the paths
  # git emits with leading or trailing whitespace.
  defp submodule_paths(repository_directory, path_prefix) do
    case System.cmd("git", ["-C", repository_directory, "ls-files", "--stage", "-z"], stderr_to_stdout: true) do
      {output, 0} ->
        paths =
          output
          |> String.split(<<0>>, trim: true)
          |> Enum.filter(&String.starts_with?(&1, "160000"))
          |> Enum.map(fn record ->
            case String.split(record, "\t", parts: 2) do
              [_, path] -> path
              _ -> nil
            end
          end)
          # A submodule git left unpopulated lists the superproject's own gitlink
          # back as `./`, which would walk the tree into itself.
          |> Enum.reject(&(&1 in [nil, "", ".", "./"]))

        {:ok, paths}

      {output, status} ->
        {:error, {:git_list_submodules_failed, path_prefix || ".", status, String.trim(output)}}
    end
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
      # `-y` stores the symlinks that `resolve_symlinks/1` deliberately preserved
      # (those inside code-signed bundles) as symlinks instead of following them
      # and inlining their target, which would otherwise break the signature.
      case System.cmd("zip", ["-r", "-y", archive_path, base_name], cd: parent_dir) do
        {_, 0} -> :ok
        {output, status} -> {:error, {:zip_failed, status, output}}
      end
    end
  end

  defp resolve_symlinks(directory) do
    case System.cmd("find", [directory, "-type", "l"], stderr_to_stdout: true) do
      {output, 0} ->
        symlink_paths =
          output
          |> String.split("\n", trim: true)
          |> Enum.reject(&within_signed_bundle?/1)

        {directory_symlinks, non_directory_symlinks} = classify_symlinks(symlink_paths)

        with :ok <- resolve_non_directory_symlinks(non_directory_symlinks) do
          resolve_directory_symlinks(directory_symlinks)
        end

      {output, status} ->
        {:error, {:find_symlinks_failed, status, output}}
    end
  end

  defp within_signed_bundle?(path) do
    # Inspect only the ancestor directories, not the symlink's own basename: the
    # bundle whose sealed layout we protect is always a real directory above the
    # symlink. A root-level symlink that happens to be named like a bundle (e.g.
    # `Foo.framework -> ...`) must still be flattened, so it does not reintroduce
    # the SwiftPM root-level extraction failure on un-patched clients.
    path
    |> Path.split()
    |> Enum.drop(-1)
    |> Enum.any?(fn component ->
      Enum.any?(@signed_bundle_extensions, &String.ends_with?(component, &1))
    end)
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

  defp repackage_archive(tmp_dir, archive_path) do
    extract_dir = Path.join(tmp_dir, "extract")
    Logger.info("Repacking source archive at #{archive_path}")

    with :ok <- ensure_extract_directory(extract_dir),
         :ok <- unzip_archive(archive_path, extract_dir),
         {:ok, top_level_directory} <- extract_archive_root_directory(extract_dir),
         :ok <- remove_archive(archive_path),
         :ok <- zip_directory(top_level_directory, archive_path) do
      verify_archive_directories(archive_path)
    end
  end

  defp normalize_package_relative_path(path, base_path \\ ".") do
    package_root = "/package"
    expanded_base_path = Path.expand(base_path, package_root)
    expanded_path = Path.expand(path, expanded_base_path)

    cond do
      expanded_path == package_root ->
        nil

      path_within_root?(expanded_path, package_root) ->
        Path.relative_to(expanded_path, package_root)

      true ->
        nil
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

  # Walks the `zipinfo` listing lazily and keeps only the tallies, because a
  # large package carries tens of thousands of entries and none of them are
  # needed once counted.
  defp inspect_archive(archive_path) do
    case System.cmd("unzip", ["-Z", archive_path], stderr_to_stdout: true) do
      {output, 0} ->
        {:ok,
         output
         |> String.splitter("\n")
         |> Enum.reduce(%{symlinks?: false, unreadable_directories: 0, first_unreadable: nil}, &tally_entry/2)}

      {output, status} ->
        {:error, {:invalid_archive, status, output}}
    end
  end

  defp tally_entry("l" <> _rest, tally), do: %{tally | symlinks?: true}

  defp tally_entry(line, tally) do
    if unreadable_directory_line?(line) do
      %{
        tally
        | unreadable_directories: tally.unreadable_directories + 1,
          first_unreadable: tally.first_unreadable || String.trim(line)
      }
    else
      tally
    end
  end

  # A stored directory entry whose recorded mode has no owner-execute bit
  # extracts into a directory nobody can descend into, so SwiftPM fails with a
  # permission error on an archive that is otherwise well-formed and whose
  # checksum matches its metadata. `zipinfo` renders a healthy directory as
  # `drwxr-xr-x` and the entry this rejects as `?rw-r--r--`, so the
  # owner-execute column is the whole test and the trailing slash is what
  # marks a directory. Entries written by non-Unix hosts carry no mode at all
  # and extractors apply their own defaults, which is why this reads the
  # rendered permissions rather than the raw external attributes.
  defp unreadable_directory_line?(line) do
    String.ends_with?(line, "/") and not traversable_directory?(line)
  end

  defp traversable_directory?(<<_type, _read, _write, ?x, _rest::binary>>), do: true
  defp traversable_directory?(_line), do: false

  defp verify_archive_directories(archive_path) do
    with {:ok, listing} <- inspect_archive(archive_path) do
      reject_unreadable_directories(listing)
    end
  end

  defp reject_unreadable_directories(%{unreadable_directories: 0}), do: :ok

  defp reject_unreadable_directories(listing) do
    {:error, {:archive_directories_not_traversable, listing.unreadable_directories, listing.first_unreadable}}
  end

  # Republishing a version with different bytes turns a working pin into
  # `invalid registry source archive checksum` for every client that already
  # resolved it, and a precautionary resync is otherwise indistinguishable
  # from a repair. A resync that would change an already-published checksum
  # stops here unless the operator asked for that explicitly.
  defp ensure_checksum_change_allowed(_scope, _name, _version, _checksum, %{allow_checksum_change?: true}), do: :ok

  defp ensure_checksum_change_allowed(scope, name, version, checksum, opts) do
    case opts.published_checksum do
      nil ->
        :ok

      ^checksum ->
        :ok

      published ->
        {:error,
         {:checksum_change_refused,
          %{scope: scope, name: name, version: version, published: published, rebuilt: checksum}}}
    end
  end

  defp upload_source_archive(scope, name, version, archive_path, checksum) do
    S3.upload_file(source_archive_key(scope, name, version), archive_path,
      content_type: "application/zip",
      meta: [{"sha256", checksum}]
    )
  end

  # The archive upload runs through the multipart path, whose sub-operations do
  # not carry the storage consistency header the shared request helper adds to
  # single requests. Confirming the stored object records the digest we just
  # uploaded, before the catalog is updated, keeps a catalog entry from
  # advertising a checksum that object storage does not actually hold.
  defp verify_stored_archive(scope, name, version, checksum) do
    key = source_archive_key(scope, name, version)

    case S3.head_object(key) do
      {:ok, headers} ->
        case Map.get(headers, "x-amz-meta-sha256") do
          ^checksum -> :ok
          stored -> {:error, {:stored_archive_mismatch, key, %{expected: checksum, stored: stored}}}
        end

      {:error, reason} ->
        {:error, {:stored_archive_unverifiable, key, reason}}
    end
  end

  defp source_archive_key(scope, name, version) do
    KeyNormalizer.package_object_key(%{scope: scope, name: name},
      version: version,
      path: "source_archive.zip"
    )
  end

  defp fetch_manifests(full_handle, tag, token) do
    with {:ok, contents} <-
           TuistCommon.GitHub.list_repository_contents(full_handle, token, tag, @github_opts) do
      {manifest_payloads, failures} =
        contents
        |> Enum.map(&Map.get(&1, "path"))
        |> Enum.filter(&manifest_path?/1)
        |> Enum.reduce({[], []}, fn path, {manifest_payloads, failures} ->
          filename = Path.basename(path)

          case TuistCommon.GitHub.get_file_content(full_handle, token, path, tag, @github_opts) do
            {:ok, content} ->
              manifest_payload = %{
                content: content,
                filename: filename,
                path: path,
                swift_version: AlternateManifest.swift_version_from_filename(filename)
              }

              {[manifest_payload | manifest_payloads], failures}

            {:error, reason} ->
              Logger.warning("Failed to fetch manifest #{path} for #{full_handle}@#{tag}: #{inspect(reason)}")

              {manifest_payloads, [%{path: path, reason: reason} | failures]}
          end
        end)

      cond do
        failures != [] ->
          {:error, {:manifest_fetch_failed, Enum.reverse(failures)}}

        manifest_payloads == [] ->
          {:error, {:missing_manifests, full_handle, tag}}

        not Enum.any?(manifest_payloads, &(&1.filename == "Package.swift")) ->
          {:error, {:missing_default_manifest, full_handle, tag}}

        true ->
          {:ok, Enum.reverse(manifest_payloads)}
      end
    end
  end

  defp upload_manifests(scope, name, version, manifest_payloads) do
    {manifests, failures} =
      Enum.reduce(manifest_payloads, {[], []}, fn %{
                                                    content: content,
                                                    filename: filename,
                                                    path: path,
                                                    swift_version: swift_version
                                                  },
                                                  {manifests, failures} ->
        case upload_manifest(scope, name, version, filename, content) do
          :ok ->
            manifest = %{
              "swift_version" => swift_version,
              "swift_tools_version" => AlternateManifest.swift_tools_version(content)
            }

            {[manifest | manifests], failures}

          {:error, reason} ->
            Logger.warning("Failed to upload manifest #{path} for #{scope}/#{name}@#{version}: #{inspect(reason)}")

            {manifests, [%{path: path, reason: reason} | failures]}
        end
      end)

    if failures == [] do
      {:ok, manifests |> Enum.reverse() |> AlternateManifest.deduplicate_by_tools_version()}
    else
      {:error, {:manifest_upload_failed, Enum.reverse(failures)}}
    end
  end

  defp update_metadata_with_release(scope, name, full_handle, version, checksum, manifests) do
    lock_key = {:package, scope, name}

    case acquire_metadata_lock(lock_key) do
      {:ok, :acquired} ->
        try do
          with {:ok, metadata} <- get_or_create_metadata(scope, name, full_handle) do
            updated_metadata =
              build_updated_metadata(
                metadata,
                scope,
                name,
                full_handle,
                version,
                checksum,
                manifests
              )

            Metadata.put_package(scope, name, updated_metadata)
          end
        after
          Lock.release(lock_key)
        end

      {:error, :already_locked} ->
        Logger.info("Metadata update deferred for #{scope}/#{name}@#{version}: package lock contended, snoozing")

        {:snooze, @metadata_lock_snooze_seconds}
    end
  end

  # Sibling ReleaseWorker jobs from the same sync batch contend for this
  # per-package S3 lock, which is only held for a metadata read + write
  # (sub-second). The release write happens after the source archive and
  # manifests are already uploaded, so a short in-job retry finishes the job
  # rather than snoozing and redoing that GitHub + S3 work. Callers snooze when
  # the retry budget is exhausted (e.g. a crashed holder's lock lingering until
  # its TTL). The skipped-release write has nothing expensive to redo, so it
  # deliberately does not use this and snoozes immediately instead.
  defp acquire_metadata_lock(lock_key) do
    acquire_metadata_lock(lock_key, @metadata_lock_max_attempts)
  end

  defp acquire_metadata_lock(lock_key, attempts_remaining) do
    case Lock.try_acquire(lock_key, @metadata_lock_ttl_seconds) do
      {:ok, :acquired} ->
        {:ok, :acquired}

      {:error, :already_locked} when attempts_remaining > 1 ->
        Process.sleep(metadata_lock_backoff_ms(attempts_remaining))
        acquire_metadata_lock(lock_key, attempts_remaining - 1)

      {:error, :already_locked} ->
        {:error, :already_locked}
    end
  end

  defp metadata_lock_backoff_ms(attempts_remaining) do
    step = @metadata_lock_max_attempts - attempts_remaining + 1
    @metadata_lock_backoff_ms * step + :rand.uniform(@metadata_lock_backoff_ms)
  end

  # Retrying immediately re-clones the repository and every submodule already
  # walked, aimed at a host that has just asked us to slow down, and reports each
  # attempt separately. A third-party host sends no quota headers, so this backs
  # off by the default window rather than to a reported reset.
  defp maybe_skip_release(
         scope,
         name,
         _full_handle,
         version,
         {:git_submodule_update_throttled, submodule_path, _status, _output}
       ) do
    Logger.warning(
      "Deferring registry release #{scope}/#{name}@#{version} for #{@default_snooze_seconds}s: the host serving submodule #{submodule_path} is throttling requests"
    )

    :telemetry.execute(@release_deferred_event, %{releases: 1}, %{reason: :submodule_host_throttled})

    {:snooze, @default_snooze_seconds}
  end

  defp maybe_skip_release(scope, name, full_handle, version, {:missing_manifests, failed_full_handle, tag}) do
    Logger.warning(
      "Skipping registry release #{scope}/#{name}@#{tag} for #{failed_full_handle}: no root Package.swift manifest was found"
    )

    update_metadata_with_skipped_release(scope, name, full_handle, version, "missing_manifests")
  end

  defp maybe_skip_release(scope, name, full_handle, version, {:missing_default_manifest, failed_full_handle, tag}) do
    Logger.warning(
      "Skipping registry release #{scope}/#{name}@#{tag} for #{failed_full_handle}: no default Package.swift manifest was found"
    )

    update_metadata_with_skipped_release(scope, name, full_handle, version, "missing_default_manifest")
  end

  # Discarding here dropped the job's arguments, so the release was only
  # revisited if a later catalog rotation happened to notice it missing again.
  # Snoozing to the quota reset keeps the same job, with the same scope, name
  # and tag, and lets it run once the budget is back.
  defp maybe_skip_release(scope, name, _full_handle, version, reason) do
    case rate_limit_deferral(reason) do
      nil ->
        :not_skipped

      {status, retry_after} ->
        seconds = snooze_seconds(retry_after)

        Logger.warning(
          "Deferring registry release #{scope}/#{name}@#{version} for #{seconds}s after GitHub rate limit (HTTP #{status})"
        )

        :telemetry.execute(@release_deferred_event, %{releases: 1}, %{reason: :rate_limited})

        {:snooze, seconds}
    end
  end

  defp rate_limit_deferral({:rate_limited, status, retry_after}), do: {status, retry_after}

  defp rate_limit_deferral(tuple) when is_tuple(tuple) do
    tuple
    |> Tuple.to_list()
    |> Enum.find_value(&rate_limit_deferral/1)
  end

  defp rate_limit_deferral(list) when is_list(list), do: Enum.find_value(list, &rate_limit_deferral/1)

  defp rate_limit_deferral(map) when is_map(map), do: map |> Map.values() |> Enum.find_value(&rate_limit_deferral/1)

  defp rate_limit_deferral(_reason), do: nil

  defp snooze_seconds(nil), do: @default_snooze_seconds

  defp snooze_seconds(retry_after) when is_integer(retry_after) do
    retry_after |> max(@min_snooze_seconds) |> min(@max_snooze_seconds)
  end

  defp update_metadata_with_skipped_release(scope, name, full_handle, version, reason) do
    lock_key = {:package, scope, name}

    # No in-job retry: the skip write only fetched the repo contents, so there is
    # nothing expensive to redo. Snooze immediately on contention rather than
    # holding an Oban concurrency slot asleep on a backoff.
    case Lock.try_acquire(lock_key, @metadata_lock_ttl_seconds) do
      {:ok, :acquired} ->
        try do
          with {:ok, metadata} <- get_or_create_metadata(scope, name, full_handle) do
            updated_metadata =
              build_updated_metadata_with_skipped_release(
                metadata,
                scope,
                name,
                full_handle,
                version,
                reason
              )

            Metadata.put_package(scope, name, updated_metadata)
          end
        after
          Lock.release(lock_key)
        end

      {:error, :already_locked} ->
        Logger.info(
          "Skipped release metadata update deferred for #{scope}/#{name}@#{version}: package lock contended, snoozing"
        )

        {:snooze, @metadata_lock_snooze_seconds}
    end
  end

  defp get_or_create_metadata(scope, name, full_handle) do
    case Metadata.get_package(scope, name, fresh: true) do
      {:ok, metadata} ->
        {:ok, metadata}

      {:error, :not_found} ->
        {:ok,
         %{
           "scope" => scope,
           "name" => name,
           "repository_full_handle" => full_handle,
           "releases" => %{}
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_updated_metadata(metadata, scope, name, full_handle, version, checksum, manifests) do
    metadata
    |> Map.put_new("scope", scope)
    |> Map.put_new("name", name)
    |> Map.put("repository_full_handle", full_handle)
    |> Map.put(
      "updated_at",
      DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
    )
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
    |> Map.update("skipped_releases", %{}, &Map.delete(&1 || %{}, version))
  end

  defp build_updated_metadata_with_skipped_release(metadata, scope, name, full_handle, version, reason) do
    skipped_release = Metadata.verified_skip(reason)

    metadata
    |> Map.put_new("scope", scope)
    |> Map.put_new("name", name)
    |> Map.put("repository_full_handle", full_handle)
    |> Map.put(
      "updated_at",
      DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
    )
    |> Map.update(
      "skipped_releases",
      %{version => skipped_release},
      fn skipped_releases ->
        Map.put(skipped_releases || %{}, version, skipped_release)
      end
    )
  end

  defp upload_manifest(scope, name, version, filename, content) do
    key =
      KeyNormalizer.package_object_key(%{scope: scope, name: name},
        version: version,
        path: filename
      )

    S3.upload_content(key, content, content_type: "text/x-swift")
  end

  defp manifest_path?(path) when is_binary(path), do: AlternateManifest.registry_manifest_path?(path)
  defp manifest_path?(_), do: false

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
