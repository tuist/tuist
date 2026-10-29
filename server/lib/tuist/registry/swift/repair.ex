defmodule Tuist.Registry.Swift.Repair do
  @moduledoc """
  The only supported entry point for a bulk repair that can replace already
  published archive bytes.

  A package version is immutable from a client's point of view: Swift Package
  Manager records a trust-on-first-use fingerprint the first time it resolves
  one, and a later resolution whose bytes hash differently fails outright.
  Rebuilding an existing version is therefore not a neutral precaution, it is a
  content change, and the July 2026 incident turned a recovery into a second,
  larger incident by treating it as one.

  Every guard the postmortem asked for lives here:

    * **Dry run first.** `plan/2` performs no writes. It reads the catalog and
      object storage and returns a per-version inventory.
    * **Checksum-change inventory.** The plan classifies each version by whether
      replacing it can change a published checksum, so the blast radius is
      visible before anything runs.
    * **Explicit approval.** `apply_plan/2` refuses unless the caller passes back
      the plan's `:approval` digest, which covers the exact targets and the exact
      published checksums the plan was computed from. A plan the operator did not
      read cannot be applied, and a plan the live state has since moved past is
      rejected rather than applied to different bytes.
    * **Bounded batch.** A plan larger than `max_batch/0` is refused outright.
    * **Automatic abort threshold.** A plan whose checksum-changing targets
      exceed `:max_checksum_changes` is refused before a single job is enqueued.
    * **Reversible backup.** Every archive whose bytes may be replaced is copied
      to a backup key first, and `restore/4` puts it and its catalog entry back.

  The backup here covers the repair path specifically. Making ordinary
  synchronization writes physically unable to replace a published version is a
  separate, storage-layer change.

  Run from an Elixir console on a swift-registry-sync pod:

      {:ok, plan} = Repair.plan([{"auth0/Auth0.swift", "2.10.0"}])
      plan.counts
      Repair.apply_plan(plan, approval: plan.approval)
  """

  import Ecto.Query

  alias Tuist.Registry
  alias Tuist.Registry.S3
  alias Tuist.Registry.Swift.Lock
  alias Tuist.Registry.Swift.Metadata
  alias Tuist.Registry.Swift.ReleaseWorker
  alias Tuist.Registry.Swift.SyncWorker
  alias TuistCommon.Registry.Swift.KeyNormalizer

  require Logger

  @max_batch 100
  @default_max_checksum_changes 10

  # Same locks and bounds the release worker uses: `{:release, ...}` for a
  # version's whole publication, `{:package, ...}` for its catalog entry.
  @release_lock_ttl_seconds 1_800
  @metadata_lock_ttl_seconds 300
  @metadata_lock_max_attempts 5
  @metadata_lock_backoff_ms 200

  @doc """
  The largest number of versions one repair may cover.

  A repair is a manual, supervised action. Bounding it keeps a mistake to
  something an operator can inspect and roll back, instead of the 5,687 archives
  the 28 July recovery replaced in a single pass.
  """
  def max_batch, do: @max_batch

  @doc """
  Reads the current state of every target and returns the inventory a repair
  would act on. Performs no writes.

  Targets are `{repository_full_handle, version}` tuples. Each is classified as:

    * `:absent` — the catalog has no entry for the version, so no client can be
      holding a fingerprint for it and a rebuild cannot break one.
    * `:unresolvable` — the catalog advertises a checksum but object storage
      cannot back it (the archive is missing, or its stored digest disagrees
      with the catalog). Nobody has resolved this successfully, so replacing it
      is a repair rather than a content change.
    * `:published` — the catalog and object storage agree. A rebuild that
      produces different bytes breaks every client that already resolved it.

  Only `:unresolvable` targets are allowed to change a checksum, and only
  through the explicit override the release worker requires.
  """
  def plan(targets, opts \\ []) when is_list(targets) do
    with {:ok, max_checksum_changes} <-
           validate_max_checksum_changes(Keyword.get(opts, :max_checksum_changes, @default_max_checksum_changes)),
         {:ok, normalized} <- normalize_targets(targets) do
      inspected = Enum.map(normalized, &inspect_target/1)

      plan = %{
        targets: inspected,
        counts: counts(inspected),
        max_checksum_changes: max_checksum_changes,
        planned_at: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
      }

      {:ok, Map.put(plan, :approval, approval_digest(inspected, max_checksum_changes))}
    end
  end

  @doc """
  Applies a plan returned by `plan/2`.

  Refuses unless every gate passes: the caller passed the plan's own approval
  digest back, the batch is within `max_batch/0`, the number of targets allowed
  to change a checksum is within the plan's threshold, no target failed
  inspection, and the live published checksum still matches what the plan was
  computed from.

  Backs up each replaceable archive before enqueuing its rebuild, so the pass is
  reversible through `restore/4`.
  """
  def apply_plan(plan, opts) do
    with :ok <- ensure_approved(plan, opts),
         :ok <- ensure_within_batch(plan),
         :ok <- ensure_inspectable(plan),
         :ok <- ensure_within_checksum_change_threshold(plan) do
      Logger.warning(
        "Applying registry repair over #{length(plan.targets)} versions, " <>
          "#{count_status(plan.targets, :unresolvable)} of which may change a published checksum"
      )

      results = Enum.map(plan.targets, &repair_target/1)

      {:ok,
       %{
         applied: Enum.filter(results, &(&1.status == :enqueued)),
         failed: Enum.reject(results, &(&1.status == :enqueued))
       }}
    end
  end

  @doc """
  Puts a backed-up archive and its catalog entry back.

  `checksum` names the backup, which is the checksum the version advertised
  before the repair replaced it. This is the rollback the July 2026 recovery did
  not have: the bucket had no versioning, so the bytes clients had already
  trusted were gone the moment they were overwritten.

  Two things happen before any byte moves. Outstanding repair jobs for the
  version are cancelled, because a job that snoozed on a rate limit carries
  `allow_checksum_change: true` and would republish the rebuilt bytes over the
  restore hours later. And everything the restore needs is read first, so a
  missing backup or an unreadable catalog fails before the archive is replaced
  rather than halfway through.
  """
  def restore(repository_full_handle, version, checksum, _opts \\ []) do
    with {:ok, target} <- normalize_target({repository_full_handle, version}),
         {:ok, result} <- with_release_fence(target, fn -> do_restore(target, checksum) end) do
      {:ok, result}
    else
      # The archive is back but the catalog still advertises the checksum the
      # repair produced, so the version resolves to a mismatch until this is
      # re-run. Naming that state explicitly is the difference between an
      # operator retrying and an operator not knowing to.
      {:error, {:catalog_write_failed, reason}} ->
        Logger.error(
          "Restore of #{repository_full_handle}@#{version} replaced the archive but could not " <>
            "rewrite the catalog entry: #{inspect(reason)}. Re-run restore/4 to finish it."
        )

        {:error, {:restore_incomplete, :catalog_not_updated, reason}}

      {:error, _reason} = error ->
        error
    end
  end

  # Runs entirely inside the release fence, so no release for this version can
  # interleave between the archive copy and the catalog write.
  #
  # Cancellation runs twice, and the second pass is the load-bearing one. The
  # first is a point-in-time snapshot: a `SyncWorker` that was already executing
  # can insert a `ReleaseWorker` after it, and an Oban insert is not blocked by
  # the fence even though running the job is. Sweeping again before the fence is
  # released catches anything inserted while the restore was in progress.
  # Anything inserted after that is a new repair request rather than a leftover
  # of the one being rolled back.
  defp do_restore(target, checksum) do
    with {:ok, cancelled_before} <- cancel_repair_jobs(target),
         {:ok, metadata} <- Metadata.get_package(target.scope, target.name),
         :ok <- ensure_release_in_catalog(target, metadata),
         :ok <- ensure_backup_exists(target, checksum),
         :ok <- S3.copy_object(backup_archive_key(target, checksum), archive_key(target)),
         :ok <- write_restored_checksum(target, checksum),
         {:ok, cancelled_after} <- cancel_repair_jobs(target) do
      cancelled = cancelled_before + cancelled_after

      Logger.warning(
        "Restored #{target.scope}/#{target.name}@#{target.version} to checksum #{checksum}, " <>
          "cancelling #{cancelled} outstanding repair job(s)"
      )

      {:ok,
       %{
         scope: target.scope,
         name: target.name,
         version: target.version,
         checksum: checksum,
         cancelled_jobs: cancelled
       }}
    end
  end

  # Cancels every queued or running job that would write this version, so a
  # deferred repair cannot land on top of the restore after the fact. Oban
  # cannot express "the normalized form of args->>'tag' equals this version" in
  # SQL, so candidates are narrowed in the query and matched here.
  defp cancel_repair_jobs(target) do
    cancellable = ~w(available scheduled retryable executing)

    handle = String.downcase(target.repository_full_handle)

    candidates =
      from(job in Oban.Job,
        where: job.state in ^cancellable,
        where: job.worker in ^[worker_name(SyncWorker), worker_name(ReleaseWorker)],
        # Narrowed to this one package in SQL. The release queue routinely holds
        # thousands of jobs, and an operator reaches for this mid-incident, so
        # the version match is the only part left to Elixir.
        where:
          fragment("lower(? ->> 'repository_full_handle') = ?", job.args, ^handle) or
            (fragment("? ->> 'scope' = ?", job.args, ^target.scope) and
               fragment("? ->> 'name' = ?", job.args, ^target.name)),
        select: %{id: job.id, worker: job.worker, args: job.args}
      )
      |> Tuist.Repo.all()
      |> Enum.filter(&targets_version?(&1, target))
      |> Enum.map(& &1.id)

    case candidates do
      [] -> {:ok, 0}
      ids -> Oban.cancel_all_jobs(from(job in Oban.Job, where: job.id in ^ids))
    end
  end

  defp worker_name(module), do: module |> Atom.to_string() |> String.replace_prefix("Elixir.", "")

  defp targets_version?(%{worker: worker, args: args}, target) do
    if worker == worker_name(SyncWorker) do
      handle = args["repository_full_handle"]
      version = args["version"]

      is_binary(handle) and is_binary(version) and
        String.downcase(handle) == String.downcase(target.repository_full_handle) and
        KeyNormalizer.normalize_version(version) == target.version
    else
      tag = args["tag"]

      args["scope"] == target.scope and args["name"] == target.name and
        is_binary(tag) and KeyNormalizer.normalize_version(tag) == target.version
    end
  end

  defp ensure_release_in_catalog(target, metadata) do
    if metadata |> Map.get("releases", %{}) |> Map.has_key?(target.version) do
      :ok
    else
      {:error, {:release_not_in_catalog, target.version}}
    end
  end

  defp ensure_backup_exists(target, checksum) do
    case S3.head_object(backup_archive_key(target, checksum)) do
      {:ok, _headers} -> :ok
      {:error, :not_found} -> {:error, {:backup_not_found, target.version, checksum}}
      {:error, reason} -> {:error, {:backup_unreadable, reason}}
    end
  end

  @doc """
  Lists the checksums a version has backups for, newest key order aside.
  """
  def list_backups(repository_full_handle, version) do
    with {:ok, target} <- normalize_target({repository_full_handle, version}) do
      checksums =
        target
        |> backup_prefix()
        |> S3.list_keys_with_prefix!()
        |> Enum.filter(&String.ends_with?(&1, "/source_archive.zip"))
        |> Enum.map(fn key -> key |> Path.dirname() |> Path.basename() end)
        |> Enum.uniq()

      {:ok, checksums}
    end
  end

  defp repair_target(%{status: :published} = target) do
    # A version whose catalog entry and stored archive agree is left alone. The
    # release worker would refuse to change its checksum anyway; enqueuing it
    # would only spend GitHub quota to rediscover that.
    Map.merge(target, %{status: :skipped, reason: :already_consistent})
  end

  # The whole check-back-up-enqueue sequence runs under the same
  # `{:release, scope, name, version}` lock `ReleaseWorker.perform/1` holds for
  # an entire release. That is what makes the classification re-read below
  # meaningful: without it the reading is just a narrower race, since a release
  # could land between the read and the enqueue. It also serializes two
  # concurrent applies for the same version, which is what kept the
  # check-then-copy in `back_up_archive/1` from being atomic.
  defp repair_target(target) do
    case with_release_fence(target, fn -> attempt_repair(target) end) do
      {:ok, repaired} -> repaired
      {:skip, reason} -> Map.merge(target, %{status: :skipped, reason: reason})
      {:error, reason} -> Map.merge(target, %{status: :failed, reason: reason})
    end
  end

  defp attempt_repair(target) do
    with {:ok, current} <- refreshed_target(target),
         :ok <- back_up_archive(current),
         {:ok, _job} <-
           Registry.force_resync_swift_package_version(
             current.repository_full_handle,
             current.version,
             allow_checksum_change: current.status == :unresolvable
           ) do
      {:ok, Map.put(current, :status, :enqueued)}
    end
  end

  # The permission to change a published checksum is granted from this reading,
  # never from the plan's. The plan's classification can be minutes old, and it
  # has two halves: the catalog checksum and the stored archive. Re-reading only
  # the catalog half left the dangerous case open — if anything restored the
  # archive to the published checksum in between, the version is healthy again
  # while the catalog checksum is unchanged, so a stale `:unresolvable` would
  # have carried the override into replacing a perfectly good published archive.
  # That is the exact harm this module exists to prevent.
  defp refreshed_target(target) do
    current = inspect_target(target)

    cond do
      current.status == :uninspectable ->
        {:error, {:target_uninspectable, Map.get(current, :reason)}}

      current.published_checksum != target.published_checksum ->
        {:error, {:published_checksum_moved, target.published_checksum, current.published_checksum}}

      # Repaired by something else since the plan was read. Nothing to do, and
      # nothing that would justify replacing its bytes.
      current.status == :published ->
        {:skip, :already_consistent}

      current.status != target.status ->
        {:error, {:target_state_moved, target.status, current.status}}

      true ->
        {:ok, current}
    end
  end

  # Mutual exclusion with release execution for one version. `ReleaseWorker`
  # takes this same key for the whole of `do_sync_release/5`, which covers both
  # the archive upload and the catalog write, so holding it here is what keeps a
  # release from interleaving with a repair or a rollback of the same version.
  # `Lock.try_acquire/2` is an `If-None-Match: *` conditional create, so it is a
  # real mutex rather than a read-then-write check.
  defp with_release_fence(target, fun) do
    lock_key = {:release, target.scope, target.name, target.version}

    case Lock.try_acquire(lock_key, @release_lock_ttl_seconds) do
      {:ok, :acquired} ->
        try do
          fun.()
        after
          Lock.release(lock_key)
        end

      {:error, :already_locked} ->
        {:error, :release_in_flight}
    end
  end

  defp back_up_archive(%{published_checksum: nil}), do: :ok

  # Write-once. The key is derived from the published checksum, and a repair can
  # legitimately run more than once against the same one: the release worker
  # replaces the archive before it writes the catalog entry, so a rebuild that
  # fails in between (read-back verification, manifest upload, a contended
  # metadata lock) leaves new bytes under an unchanged catalog checksum. The
  # obvious re-plan then classifies the version as unresolvable and would copy
  # those new bytes over the only remaining copy of the pre-repair ones, at the
  # same key. With no bucket versioning that is unrecoverable, which is the
  # condition this backup exists to avoid in the first place.
  #
  # Keeping the first backup is the correct choice rather than merely the safe
  # one: it is the state the version was in before any repair touched it, which
  # is what a rollback wants.
  defp back_up_archive(target) do
    checksum = target.published_checksum
    destination = backup_archive_key(target, checksum)

    case S3.head_object(destination) do
      {:ok, _headers} ->
        Logger.info("Keeping the existing pre-repair backup of #{target.scope}/#{target.name}@#{target.version}")

        :ok

      {:error, :not_found} ->
        write_backup(target, checksum, destination)

      {:error, reason} ->
        {:error, {:backup_unreadable, reason}}
    end
  end

  defp write_backup(target, checksum, destination) do
    with :ok <- S3.copy_object(archive_key(target), destination),
         :ok <- write_backup_manifest(target, checksum) do
      Logger.info("Backed up #{target.scope}/#{target.name}@#{target.version} (#{checksum}) to #{destination}")

      :ok
    else
      # A version the catalog advertises but object storage cannot produce has
      # nothing to back up, and refusing to repair it would leave it broken
      # forever. Every other copy failure stops the target.
      {:error, :not_found} -> :ok
      {:error, reason} -> {:error, {:backup_failed, reason}}
    end
  end

  defp write_backup_manifest(target, checksum) do
    body =
      JSON.encode!(%{
        "scope" => target.scope,
        "name" => target.name,
        "version" => target.version,
        "repository_full_handle" => target.repository_full_handle,
        "published_checksum" => checksum,
        "source_key" => archive_key(target),
        "backed_up_at" => DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
      })

    S3.upload_content(backup_manifest_key(target, checksum), body, content_type: "application/json")
  end

  # The catalog entry is one document per package, so writing it is a
  # read-modify-write shared with release publication, which takes this same
  # `{:package, scope, name}` lock. Two things follow, and both matter.
  #
  # The metadata is re-read inside the lock rather than reused from the
  # pre-flight read above. Between the two there is an archive copy, which for a
  # large package is not quick, and any version published in that window exists
  # only in the newer document. Writing back the older one would drop it. That
  # is a stale full-document overwrite, which is the first root cause the July
  # 2026 postmortem records, and there is no reason for the rollback path to
  # reintroduce it.
  #
  # The lock is taken here rather than around the whole restore so it covers
  # only a sub-second read and write, matching what the release worker holds it
  # for. Holding it across the archive copy would block release publication for
  # that package for as long as the copy takes, and could outlive the lock's own
  # time to live.
  defp write_restored_checksum(target, checksum) do
    lock_key = {:package, target.scope, target.name}

    case acquire_metadata_lock(lock_key, @metadata_lock_max_attempts) do
      {:ok, :acquired} ->
        try do
          put_restored_checksum(target, checksum)
        after
          Lock.release(lock_key)
        end

      {:error, :already_locked} ->
        {:error, {:catalog_write_failed, :package_lock_contended}}
    end
  end

  defp acquire_metadata_lock(lock_key, attempts_remaining) do
    case Lock.try_acquire(lock_key, @metadata_lock_ttl_seconds) do
      {:ok, :acquired} ->
        {:ok, :acquired}

      {:error, :already_locked} when attempts_remaining > 1 ->
        Process.sleep(@metadata_lock_backoff_ms)
        acquire_metadata_lock(lock_key, attempts_remaining - 1)

      {:error, :already_locked} ->
        {:error, :already_locked}
    end
  end

  defp put_restored_checksum(target, checksum) do
    with {:ok, metadata} <- Metadata.get_package(target.scope, target.name),
         :ok <- ensure_release_in_catalog(target, metadata) do
      releases = Map.get(metadata, "releases", %{})
      release = Map.get(releases, target.version, %{})

      updated =
        metadata
        |> Map.put("releases", Map.put(releases, target.version, Map.put(release, "checksum", checksum)))
        |> Map.put("updated_at", DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601())

      case Metadata.put_package(target.scope, target.name, updated) do
        :ok -> :ok
        {:error, reason} -> {:error, {:catalog_write_failed, reason}}
      end
    else
      {:error, reason} -> {:error, {:catalog_write_failed, reason}}
    end
  end

  defp inspect_target(target) do
    case published_checksum(target) do
      {:ok, nil} ->
        Map.merge(target, %{published_checksum: nil, stored_checksum: nil, status: :absent})

      {:ok, published} ->
        classify_published(target, published)

      {:error, reason} ->
        Map.merge(target, %{published_checksum: nil, stored_checksum: nil, status: :uninspectable, reason: reason})
    end
  end

  defp classify_published(target, published) do
    case stored_checksum(target) do
      {:ok, ^published} ->
        Map.merge(target, %{published_checksum: published, stored_checksum: published, status: :published})

      {:ok, stored} ->
        Map.merge(target, %{published_checksum: published, stored_checksum: stored, status: :unresolvable})

      {:error, :not_found} ->
        Map.merge(target, %{published_checksum: published, stored_checksum: nil, status: :unresolvable})

      {:error, reason} ->
        Map.merge(target, %{published_checksum: published, stored_checksum: nil, status: :uninspectable, reason: reason})
    end
  end

  defp published_checksum(target) do
    case Metadata.get_package(target.scope, target.name) do
      {:ok, metadata} ->
        checksum =
          metadata
          |> Map.get("releases", %{})
          |> Map.get(target.version, %{})
          |> Map.get("checksum")

        {:ok, checksum}

      {:error, :not_found} ->
        {:ok, nil}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp stored_checksum(target) do
    case S3.head_object(archive_key(target)) do
      {:ok, headers} -> {:ok, Map.get(headers, "x-amz-meta-sha256")}
      {:error, reason} -> {:error, reason}
    end
  end

  defp counts(targets) do
    Enum.reduce(
      targets,
      %{absent: 0, unresolvable: 0, published: 0, uninspectable: 0},
      &Map.update!(&2, &1.status, fn count -> count + 1 end)
    )
  end

  # Covers every field of every target that execution reads, plus the abort
  # threshold, so a digest only matches a plan that was actually read, that
  # still describes the same content, and whose gates have not been widened.
  #
  # `repository_full_handle` is signed even though `scope` and `name` are:
  # normalization is lossy, so the handle cannot be derived back from them, and
  # it is the field `repair_target/1` actually hands to the release path. Left
  # unsigned, editing only the handle kept the approval valid while pointing the
  # rebuild at a different catalog package than the one that was backed up.
  defp approval_digest(targets, max_checksum_changes) do
    targets
    |> Enum.map_join("\n", fn target ->
      "#{target.repository_full_handle}|#{target.scope}/#{target.name}@#{target.version}:" <>
        "#{target.status}:#{target.published_checksum}"
    end)
    |> Kernel.<>("\nmax_checksum_changes:#{max_checksum_changes}")
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  # Recomputes the digest from the plan as handed in rather than trusting the
  # `:approval` field carried on it, so editing any covered field invalidates
  # the approval instead of travelling with it.
  defp ensure_approved(plan, opts) do
    expected = approval_digest(plan.targets, Map.get(plan, :max_checksum_changes, @default_max_checksum_changes))

    case Keyword.get(opts, :approval) do
      approval when approval == expected -> :ok
      _ -> {:error, :approval_required}
    end
  end

  defp ensure_within_batch(%{targets: targets}) when length(targets) > @max_batch do
    {:error, {:batch_too_large, length(targets), @max_batch}}
  end

  defp ensure_within_batch(%{targets: []}), do: {:error, :empty_plan}
  defp ensure_within_batch(_plan), do: :ok

  # Both gates below count the signed targets rather than reading the plan's
  # `:counts` field. That field is a convenience for a human reading the plan
  # and is not covered by the approval digest, so a gate that trusted it could
  # be waved through by editing a number the digest never saw.

  # A target whose current state could not be read is a target whose backup and
  # blast radius are both unknown, so the whole plan stops rather than acting on
  # the ones that happened to read cleanly.
  defp ensure_inspectable(%{targets: targets}) do
    case count_status(targets, :uninspectable) do
      0 -> :ok
      count -> {:error, {:uninspectable_targets, count}}
    end
  end

  # Reads the threshold rather than pattern-matching it, so a plan missing the
  # key falls back to the default instead of matching a catch-all clause and
  # skipping the gate entirely.
  defp ensure_within_checksum_change_threshold(%{targets: targets} = plan) do
    with {:ok, threshold} <-
           validate_max_checksum_changes(Map.get(plan, :max_checksum_changes, @default_max_checksum_changes)) do
      count = count_status(targets, :unresolvable)

      if count > threshold do
        {:error, {:too_many_checksum_changes, count, threshold}}
      else
        :ok
      end
    end
  end

  # Validated at both ends, and never coerced. Elixir orders every number below
  # every binary and atom, so `count > "10"` and `count > nil` are both false:
  # a threshold typed as a string, or a key present with a nil value, would
  # silently disable the abort gate for every batch it guards rather than
  # erroring. A gate that fails open is worse than no gate, because the plan
  # still reads as though it has one.
  defp validate_max_checksum_changes(value) when is_integer(value) and value >= 0, do: {:ok, value}
  defp validate_max_checksum_changes(value), do: {:error, {:invalid_max_checksum_changes, value}}

  defp count_status(targets, status), do: Enum.count(targets, &(&1.status == status))

  defp normalize_targets([]), do: {:error, :empty_plan}

  defp normalize_targets(targets) do
    Enum.reduce_while(targets, {:ok, []}, fn target, {:ok, acc} ->
      case normalize_target(target) do
        {:ok, normalized} -> {:cont, {:ok, acc ++ [normalized]}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp normalize_target({repository_full_handle, version})
       when is_binary(repository_full_handle) and is_binary(version) do
    normalized_version = KeyNormalizer.normalize_version(version)

    case String.split(repository_full_handle, "/") do
      [raw_scope, raw_name] ->
        if KeyNormalizer.valid_storage_version?(normalized_version) do
          {scope, name} = KeyNormalizer.normalize_scope_name(raw_scope, raw_name)

          {:ok,
           %{
             repository_full_handle: repository_full_handle,
             scope: scope,
             name: name,
             version: normalized_version
           }}
        else
          {:error, {:invalid_version, version}}
        end

      _ ->
        {:error, {:invalid_repository_full_handle, repository_full_handle}}
    end
  end

  defp normalize_target(target), do: {:error, {:invalid_target, target}}

  defp archive_key(target) do
    KeyNormalizer.package_object_key(%{scope: target.scope, name: target.name},
      version: target.version,
      path: "source_archive.zip"
    )
  end

  defp backup_prefix(target), do: "registry/backups/swift/#{target.scope}/#{target.name}/#{target.version}/"

  defp backup_archive_key(target, checksum), do: backup_prefix(target) <> "#{checksum}/source_archive.zip"

  defp backup_manifest_key(target, checksum), do: backup_prefix(target) <> "#{checksum}/backup.json"
end
