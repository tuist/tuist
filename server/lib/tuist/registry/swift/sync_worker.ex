defmodule Tuist.Registry.Swift.SyncWorker do
  @moduledoc """
  Cron-driven worker. Fetches the SwiftPackageIndex catalog every 10
  minutes (cron entry is registered on the `:web` pod's leader; this
  worker runs the resulting jobs in `TUIST_MODE=swift_registry_sync`).
  Rotates through the catalog in fixed-size batches via a cursor in S3,
  and enqueues `ReleaseWorker` jobs for tags missing from each
  package's metadata.
  """

  use Oban.Worker, queue: :swift_registry_sync

  alias Tuist.Registry
  alias Tuist.Registry.Swift.Lock
  alias Tuist.Registry.Swift.Metadata
  alias Tuist.Registry.Swift.ReleaseWorker
  alias Tuist.Registry.Swift.SwiftPackageIndex
  alias Tuist.Registry.Swift.SyncCursor
  alias TuistCommon.Registry.Swift.KeyNormalizer

  require Logger

  @github_opts [finch: Tuist.Finch, retry: false]

  @sync_lock_ttl_seconds 3_000
  @package_lock_ttl_seconds 900

  # Emitted when a pass stops short of the packages it was scheduled to visit.
  # A ready pod that is silently skipping packages is the condition that let the
  # July 2026 catalog drift run for days, so lost coverage has to be a signal in
  # its own right rather than a line in the log.
  @coverage_deferred_event [:tuist, :registry, :swift, :sync, :coverage_deferred]
  @package_skipped_event [:tuist, :registry, :swift, :sync, :package_skipped]

  # GitHub's primary quota window is an hour, so the reset it reports is never
  # further out than that. The floor keeps a reset that has already elapsed from
  # turning into an immediate re-run against a quota that has not actually
  # recovered.
  @min_snooze_seconds 60
  @max_snooze_seconds 3_600
  @default_snooze_seconds 600

  @doc false
  def coverage_deferred_event_name, do: @coverage_deferred_event

  @doc false
  def package_skipped_event_name, do: @package_skipped_event

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    cond do
      not Registry.swift_registry_sync_enabled?() ->
        Logger.debug("Registry sync skipped: registry sync is disabled")
        :ok

      not Registry.swift_registry_enabled?() ->
        Logger.debug("Registry sync skipped: registry is not configured")
        :ok

      true ->
        case Registry.swift_registry_github_token() do
          nil ->
            # Configuration says the mirror has a credential, so a missing token
            # here is the App failing to issue one. Deferring keeps the pass
            # queued for when it recovers instead of reporting a clean run that
            # visited nothing.
            Logger.error("Registry sync deferred: no GitHub credential could be resolved")

            :telemetry.execute(@coverage_deferred_event, %{packages: 0}, %{reason: :missing_credential})

            {:snooze, @default_snooze_seconds}

          token ->
            perform_sync(args, token)
        end
    end
  end

  defp perform_sync(
         %{"force" => true, "repository_full_handle" => repository_full_handle, "version" => version} = args,
         token
       ) do
    resync_flags = [force: true, allow_checksum_change: Map.get(args, "allow_checksum_change", false)]
    force_resync_package_version_for_handle(repository_full_handle, version, resync_flags, token)
  end

  defp perform_sync(args, token) do
    case Lock.try_acquire(:sync, @sync_lock_ttl_seconds) do
      {:ok, :acquired} ->
        try do
          sync_packages(args, token)
        after
          Lock.release(:sync)
        end

      {:error, :already_locked} ->
        Logger.debug("Registry sync skipped: another node is the leader")
        :ok
    end
  end

  defp sync_packages(args, token) do
    limit = Map.get(args, "limit", Registry.swift_registry_sync_limit())

    case list_packages(token) do
      {:ok, []} ->
        :ok

      {:ok, packages} ->
        {batch, cursor, total} = take_batch(packages, limit)
        sync_batch(batch, cursor, total, token)

      {:snooze, _seconds} = snooze ->
        snooze

      {:discard, _reason} = discard ->
        discard

      {:error, _reason} = error ->
        error
    end
  end

  # The cursor advances only over packages the pass actually visited. Advancing
  # it by the whole batch after stopping early is what made throttled packages
  # invisible: each skipped package waited a full catalog rotation for another
  # look, with nothing recording that it had been passed over.
  defp sync_batch(batch, cursor, total, token) do
    {visited, failed, outcome} =
      Enum.reduce_while(batch, {0, 0, :ok}, fn package, {visited, failed, :ok} ->
        case sync_package(package, token) do
          :ok -> {:cont, {visited + 1, failed, :ok}}
          :failed -> {:cont, {visited + 1, failed + 1, :ok}}
          {halt_reason, retry_after} -> {:halt, {visited, failed, {halt_reason, retry_after}}}
        end
      end)

    finish_batch(batch, cursor, total, visited, failed, outcome)
  end

  defp finish_batch(batch, cursor, total, visited, _failed, {reason, retry_after}) do
    SyncCursor.put(next_cursor(cursor, visited, total))

    seconds = snooze_seconds(retry_after)
    deferred = length(batch) - visited

    Logger.warning("Deferring #{deferred} of #{length(batch)} scheduled registry packages for #{seconds}s (#{reason})")

    :telemetry.execute(@coverage_deferred_event, %{packages: deferred}, %{reason: reason})

    {:snooze, seconds}
  end

  # A pass where every package failed is a problem with the mirror, not with
  # several hundred unrelated repositories at once. Per-package failures are
  # individually survivable, which is exactly why they add up to a clean-looking
  # run: the cursor rotates on, the pass returns `:ok`, and the catalog quietly
  # stops moving. Reading "all of them" as one systemic failure is what keeps a
  # credential or client regression from hiding inside per-package noise —
  # GitHub answers a repository a credential cannot see with 404, not 401, so
  # the authentication halt above cannot catch that shape on its own.
  #
  # The cursor is held rather than advanced: nothing was mirrored, so there is
  # no progress to record, and rotating on would spend the next pass on
  # different packages that fail the same way.
  defp finish_batch(batch, cursor, _total, _visited, failed, :ok) when failed > 0 and failed == length(batch) do
    SyncCursor.put(cursor)

    Logger.error("Every one of the #{failed} packages in this registry pass failed; holding the cursor")

    :telemetry.execute(@coverage_deferred_event, %{packages: failed}, %{reason: :all_packages_failed})

    {:snooze, @default_snooze_seconds}
  end

  defp finish_batch(_batch, cursor, total, visited, _failed, :ok) do
    SyncCursor.put(next_cursor(cursor, visited, total))

    :ok
  end

  defp next_cursor(_cursor, _visited, 0), do: 0
  defp next_cursor(cursor, visited, total), do: rem(cursor + visited, total)

  defp snooze_seconds(nil), do: @default_snooze_seconds

  defp snooze_seconds(retry_after) when is_integer(retry_after) do
    retry_after |> max(@min_snooze_seconds) |> min(@max_snooze_seconds)
  end

  defp force_resync_package_version_for_handle(repository_full_handle, version, resync_flags, token) do
    normalized_version = KeyNormalizer.normalize_version(version)

    if KeyNormalizer.valid_storage_version?(normalized_version) do
      case list_packages(token) do
        {:ok, packages} ->
          case Enum.find(
                 packages,
                 &(String.downcase(&1.repository_full_handle) ==
                     String.downcase(repository_full_handle))
               ) do
            nil ->
              Logger.warning("Registry force resync skipped: package is not in the catalog: #{repository_full_handle}")

              {:discard, :package_not_found}

            package ->
              force_resync_package_version(package, normalized_version, resync_flags, token)
          end

        {:snooze, _seconds} = snooze ->
          snooze

        {:discard, _reason} = discard ->
          discard

        {:error, _reason} = error ->
          error
      end
    else
      Logger.warning("Registry force resync skipped: invalid version #{version} for #{repository_full_handle}")

      {:discard, :invalid_version}
    end
  end

  defp list_packages(token) do
    case SwiftPackageIndex.list_packages(token) do
      {:ok, packages} ->
        {:ok, apply_allowlist(packages, Registry.swift_registry_sync_allowlist())}

      {:error, reason} ->
        package_list_error(reason)
    end
  end

  # Throttling is deferred rather than dropped. Discarding it lost the pass
  # outright: the job left the queue, nothing recorded the missed coverage, and
  # the quota reset GitHub had just reported went unused.
  defp package_list_error({:rate_limited, status, retry_after}) do
    seconds = snooze_seconds(retry_after)

    Logger.warning("Deferring the Swift Package Index catalog fetch for #{seconds}s after HTTP #{status}")

    :telemetry.execute(@coverage_deferred_event, %{packages: 0}, %{reason: :rate_limited})

    {:snooze, seconds}
  end

  defp package_list_error(reason) do
    if transient_fetch_error?(reason) do
      # A transport or protocol failure talking to GitHub (connection closed
      # mid-flight, timeout, or name resolution failure). This is a cron worker that
      # fires every 10 minutes, so the next tick retries for free.
      # Retrying the Oban job instead just replays the same failure up
      # to max_attempts and pages Sentry each time for something
      # un-actionable. Discard quietly; the warning keeps it in logs.
      Logger.warning("Skipping Swift Package Index list fetch after transient error: #{inspect(reason)}")
      {:discard, reason}
    else
      # Non-throttling response-status failures (5xx, authentication, or scope
      # problems) can be persistent and are worth surfacing, so they stay a hard
      # error that retries and reports.
      Logger.error("Failed to fetch Swift Package Index list: #{inspect(reason)}")
      {:error, reason}
    end
  end

  defp transient_fetch_error?(%Req.TransportError{}), do: true
  defp transient_fetch_error?(%Req.HTTPError{}), do: true
  defp transient_fetch_error?(_reason), do: false

  defp sync_package(%{scope: scope, name: name, repository_full_handle: full_handle}, token) do
    lock_key = {:package, scope, name}

    case Lock.try_acquire(lock_key, @package_lock_ttl_seconds) do
      {:ok, :acquired} ->
        try do
          do_sync_package(scope, name, full_handle, token)
        after
          Lock.release(lock_key)
        end

      # A release worker holds this lock while it writes the package's catalog
      # entry, so contention is ordinary rather than exotic. The pass moves on
      # instead of stalling the whole rotation behind one package, and the
      # cursor moves with it, but the miss is counted: coverage the pass did not
      # take has to be visible somewhere other than in nobody's memory.
      {:error, :already_locked} ->
        Logger.debug("Skipping #{scope}/#{name}: another worker holds its package lock")

        :telemetry.execute(@package_skipped_event, %{packages: 1}, %{reason: :package_locked})

        :ok
    end
  end

  defp force_resync_package_version(
         %{scope: scope, name: name, repository_full_handle: full_handle},
         version,
         resync_flags,
         token
       ) do
    do_force_resync_package_version(scope, name, full_handle, version, resync_flags, token)
  end

  defp do_sync_package(scope, name, full_handle, token) do
    metadata =
      case Metadata.get_package(scope, name) do
        {:ok, metadata} -> metadata
        {:error, :not_found} -> empty_metadata(scope, name, full_handle)
      end

    case TuistCommon.GitHub.list_tags(full_handle, token, @github_opts) do
      {:ok, tags} ->
        sync_tags(scope, name, full_handle, tags, metadata)

      # The pass stops here rather than moving on. Continuing spends the rest of
      # the batch against an exhausted quota and skips every one of those
      # packages for a full catalog rotation, which is how thousands of
      # rate-limit failures coexisted with a pod reporting healthy.
      {:error, {:rate_limited, status, retry_after}} ->
        Logger.warning("GitHub is throttling the mirror (HTTP #{status}); stopping the pass at #{scope}/#{name}")

        {:rate_limited, retry_after}

      # A 401 is the credential, not the repository, so every remaining package
      # in the batch would fail the same way. Skipping them one by one would
      # advance the cursor over the whole batch and report a clean pass, which
      # is the silent loss of coverage this worker exists to make impossible.
      # A 403 is left as a per-package skip: GitHub uses it for repositories
      # that are individually unavailable, and halting on one would stall the
      # rotation indefinitely.
      {:error, {:http_error, 401}} ->
        Logger.error("GitHub rejected the mirror's credential at #{scope}/#{name}; stopping the pass")

        {:unauthorized, nil}

      {:error, reason} ->
        Logger.warning("Failed to fetch tags for #{scope}/#{name}: #{inspect(reason)}")

        :telemetry.execute(@package_skipped_event, %{packages: 1}, %{reason: :tag_fetch_failed})

        :failed
    end
  end

  # The rebuilt archive replaces the stored one and the catalog entry is
  # rewritten in place, so nothing is purged first. Deleting the artifact and
  # dropping the release ahead of the rebuild made the version resolve as "not
  # found" for the length of the repair, and left it permanently missing when
  # the rebuild then failed.
  defp do_force_resync_package_version(scope, name, full_handle, version, resync_flags, token) do
    case TuistCommon.GitHub.list_tags(full_handle, token, @github_opts) do
      {:ok, tags} ->
        case source_tag_for_version(tags, version) do
          nil ->
            Logger.warning("Registry force resync skipped: version #{version} is not a current tag for #{full_handle}")

            {:discard, :version_not_found}

          tag ->
            enqueue_release_worker(scope, name, full_handle, tag, resync_flags)
        end

      {:error, {:rate_limited, status, retry_after}} ->
        seconds = snooze_seconds(retry_after)

        Logger.warning(
          "Deferring the force resync of #{scope}/#{name}@#{version} for #{seconds}s after HTTP #{status} from GitHub"
        )

        {:snooze, seconds}

      {:error, reason} ->
        Logger.warning("Failed to fetch tags before force resyncing #{scope}/#{name}@#{version}: #{inspect(reason)}")

        {:error, reason}
    end
  end

  defp source_tag_for_version(tags, version) do
    Enum.find(tags, fn tag ->
      KeyNormalizer.valid_source_tag?(tag) and
        not String.ends_with?(tag, "-dev") and
        KeyNormalizer.normalize_version(tag) == version
    end)
  end

  defp sync_tags(scope, name, full_handle, tags, metadata) do
    missing_versions = missing_versions(tags, metadata)
    updated_metadata = update_metadata(metadata, scope, name, full_handle)
    :ok = Metadata.put_package(scope, name, updated_metadata)
    enqueue_release_workers(scope, name, full_handle, missing_versions)
    :ok
  end

  defp missing_versions(tags, metadata) do
    releases = Map.get(metadata, "releases", %{})
    skipped_releases = Map.get(metadata, "skipped_releases", %{})

    verified_skipped_versions =
      skipped_releases
      |> Enum.filter(fn {_version, release} -> Metadata.verified_skip?(release) end)
      |> Enum.map(&elem(&1, 0))

    known_versions = Map.keys(releases) ++ verified_skipped_versions

    tags
    |> Enum.filter(&KeyNormalizer.valid_source_tag?/1)
    |> Enum.reject(&String.ends_with?(&1, "-dev"))
    |> Enum.uniq_by(&KeyNormalizer.normalize_version/1)
    |> Enum.filter(fn tag ->
      normalized = KeyNormalizer.normalize_version(tag)
      KeyNormalizer.valid_storage_version?(normalized) and normalized not in known_versions
    end)
  end

  defp enqueue_release_workers(scope, name, full_handle, versions) do
    Enum.each(versions, fn tag ->
      enqueue_release_worker(scope, name, full_handle, tag)
    end)
  end

  defp enqueue_release_worker(scope, name, full_handle, tag, resync_flags \\ []) do
    args =
      Enum.reduce(resync_flags, %{scope: scope, name: name, repository_full_handle: full_handle, tag: tag}, fn
        {_flag, false}, args -> args
        {flag, value}, args -> Map.put(args, flag, value)
      end)

    case args |> ReleaseWorker.new() |> Oban.insert() do
      {:ok, _job} -> :ok
      {:error, _reason} = error -> error
    end
  end

  defp update_metadata(metadata, scope, name, full_handle) do
    metadata
    |> Map.put_new("scope", scope)
    |> Map.put_new("name", name)
    |> Map.put("repository_full_handle", full_handle)
    |> Map.put_new("releases", %{})
    |> Map.put(
      "updated_at",
      DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
    )
  end

  defp empty_metadata(scope, name, full_handle) do
    %{
      "scope" => scope,
      "name" => name,
      "repository_full_handle" => full_handle,
      "releases" => %{},
      "updated_at" => DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
    }
  end

  defp apply_allowlist(packages, nil), do: packages
  defp apply_allowlist(packages, []), do: packages

  defp apply_allowlist(packages, allowlist) when is_list(allowlist) do
    Enum.filter(packages, fn package ->
      Enum.any?(allowlist, fn pattern ->
        matches_pattern?(package.repository_full_handle, pattern)
      end)
    end)
  end

  defp take_batch(packages, limit) do
    total = length(packages)
    safe_limit = max(min(limit, total), 0)
    cursor = SyncCursor.get()
    cursor = if total == 0, do: 0, else: rem(max(cursor, 0), total)

    {prefix, suffix} = Enum.split(packages, cursor)
    rotated = suffix ++ prefix
    batch = Enum.take(rotated, safe_limit)

    {batch, cursor, total}
  end

  defp matches_pattern?(handle, pattern) do
    handle = String.downcase(handle)
    pattern = String.downcase(pattern)

    if String.ends_with?(pattern, "*") do
      prefix = String.trim_trailing(pattern, "*")
      String.starts_with?(handle, prefix)
    else
      handle == pattern
    end
  end
end
