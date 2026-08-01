# Applies the three repairs the audit produced. Dry-run unless REPAIR_APPLY=1.
#
#   REPAIR_MODE=catalog_restore  work order 2 — archive intact, catalog entry gone.
#                                Writes only metadata; the archive is never touched,
#                                so every pinned consumer is healed with no checksum
#                                change and nothing to announce.
#
#   REPAIR_MODE=regenerate       work orders 1 and 4 — the archive cannot be
#                                extracted, or the catalog advertises a version
#                                storage does not hold. Both are unusable today, so
#                                regenerating breaks no working pin. Enqueues the
#                                ordinary release worker with the explicit
#                                checksum-change override rather than reimplementing
#                                the build.
#
# Resumable: every decision is appended to REPAIR_LOG and idents already recorded
# there are skipped, so a run can be interrupted or repeated freely.
#
#   REPAIR_INPUT   CSV from the audit (package,version,...)
#   REPAIR_LIMIT   entries to process this run (default 100)
#   REPAIR_APPLY   "1" to write; anything else reports what it would do
#   REPAIR_LOG     default /tmp/repair_log.tsv
#   REPAIR_VERIFY  "0" to trust the published checksum instead of hashing the
#                  stored archive. Default hashes, because writing a catalog entry
#                  whose checksum storage does not actually hold is the exact
#                  failure this repair exists to undo.

alias Tuist.Registry
alias Tuist.Registry.S3
alias Tuist.Registry.Swift.Lock
alias Tuist.Registry.Swift.Metadata
alias TuistCommon.Registry.Swift.AlternateManifest
alias TuistCommon.Registry.Swift.KeyNormalizer

mode = System.fetch_env!("REPAIR_MODE")
input = System.fetch_env!("REPAIR_INPUT")
apply? = System.get_env("REPAIR_APPLY") == "1"
verify? = System.get_env("REPAIR_VERIFY", "1") == "1"
limit = String.to_integer(System.get_env("REPAIR_LIMIT", "100"))
log_path = System.get_env("REPAIR_LOG", "/tmp/repair_log.tsv")

bucket = Registry.registry_bucket()
config = Registry.registry_s3_config()

unless mode in ["catalog_restore", "regenerate"] do
  raise "REPAIR_MODE must be catalog_restore or regenerate, got #{inspect(mode)}"
end

IO.puts("mode=#{mode} apply=#{apply?} verify=#{verify?} limit=#{limit}")
IO.puts(if apply?, do: "APPLYING CHANGES", else: "dry run — nothing will be written")

done =
  if File.exists?(log_path) do
    log_path
    |> File.stream!()
    |> Stream.map(&(&1 |> String.split("\t") |> List.first()))
    |> Stream.reject(&(&1 in [nil, ""]))
    |> MapSet.new()
  else
    MapSet.new()
  end

IO.puts("already processed: #{MapSet.size(done)}")

entries =
  input
  |> File.stream!()
  |> Stream.map(&String.trim_trailing/1)
  |> Stream.reject(&(&1 == ""))
  |> Stream.drop(1)
  |> Stream.map(&String.split(&1, ",", parts: 5))
  |> Stream.filter(&(length(&1) >= 2))
  |> Stream.map(fn fields ->
    package = Enum.at(fields, 0)
    version = Enum.at(fields, 1)
    {scope, name} = package |> String.split("/", parts: 2) |> List.to_tuple()

    # Column 4 is a published checksum in catalog_missing.csv but a free-text
    # detail in unextractable.csv. Accept it only when it is actually a sha256,
    # so a detail string can never be written into a catalog entry.
    published =
      case Enum.at(fields, 3) do
        value when is_binary(value) ->
          if Regex.match?(~r/^[0-9a-f]{64}$/, value), do: value, else: nil

        _ ->
          nil
      end

    %{ident: "#{package}@#{version}", scope: scope, name: name, version: version, published: published}
  end)
  |> Stream.reject(&MapSet.member?(done, &1.ident))
  |> Stream.take(limit)
  |> Enum.to_list()

IO.puts("processing this run: #{length(entries)}\n")

version_prefix = fn scope, name, version ->
  {s, n} = KeyNormalizer.normalize_scope_name(scope, name)
  "registry/swift/#{s}/#{n}/#{KeyNormalizer.normalize_version(version)}/"
end

archive_checksum = fn key ->
  path = Path.join(System.tmp_dir!(), "repair-#{:erlang.unique_integer([:positive])}.zip")

  try do
    case bucket |> ExAws.S3.download_file(key, path) |> ExAws.request(config) do
      {:ok, _} ->
        hash =
          path
          |> File.stream!(2_048_000)
          |> Enum.reduce(:crypto.hash_init(:sha256), &:crypto.hash_update(&2, &1))
          |> :crypto.hash_final()
          |> Base.encode16(case: :lower)

        {:ok, hash}

      {:error, reason} ->
        {:error, reason}
    end
  after
    File.rm(path)
  end
end

# Rebuilds the release's manifest list from the objects already in storage, the
# same shape the release worker records: one entry per manifest, carrying the
# Swift version the filename encodes and the tools version its content declares.
stored_manifests = fn prefix ->
  keys =
    bucket
    |> ExAws.S3.list_objects_v2(prefix: prefix)
    |> ExAws.stream!(config)
    |> Stream.map(& &1.key)
    |> Enum.filter(fn key -> key |> Path.basename() |> AlternateManifest.registry_manifest_path?() end)

  Enum.reduce_while(keys, {:ok, []}, fn key, {:ok, acc} ->
    case S3.get_object(key) do
      {:ok, content} ->
        manifest = %{
          "swift_version" => AlternateManifest.swift_version_from_filename(Path.basename(key)),
          "swift_tools_version" => AlternateManifest.swift_tools_version(content)
        }

        {:cont, {:ok, [manifest | acc]}}

      {:error, reason} ->
        {:halt, {:error, {:manifest_unreadable, key, reason}}}
    end
  end)
end

# `Metadata` sanitizes on both read and write: a version whose identifier is not
# a valid storage version is invisible to `get_package/2` and stripped again by
# `put_package/3`. Restoring one is therefore not merely useless — the write
# would rewrite the whole document and silently drop every other non-normalized
# entry it still holds, including `skipped_releases`, which would make the sync
# re-enqueue and rebuild those versions. Such archives cannot be served by any
# code path and are dead storage, not a repair.
storage_version? = fn version ->
  if KeyNormalizer.valid_storage_version?(version),
    do: :ok,
    else: {:skip, :not_a_storage_version}
end

restore_catalog_entry = fn entry ->
  %{scope: scope, name: name, version: version, published: published} = entry
  prefix = version_prefix.(scope, name, version)
  archive_key = prefix <> "source_archive.zip"

  # Deliberately not S3.head_object/1: that helper ships with the fix PR, and
  # this repair must be runnable against the currently deployed release.
  archive_present? = fn key ->
    case bucket |> ExAws.S3.head_object(key) |> ExAws.request(config) do
      {:ok, %{status_code: 200}} -> :ok
      {:ok, %{status_code: status}} -> {:error, {:archive_missing, status}}
      {:error, {:http_error, status, _}} -> {:error, {:archive_missing, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  with :ok <- storage_version?.(version),
       {:ok, metadata} <- Metadata.get_package(scope, name),
       false <- Map.has_key?(Map.get(metadata, "releases", %{}) || %{}, version),
       :ok <- archive_present?.(archive_key),
       {:ok, checksum} <-
         (if verify? or published in [nil, ""],
            do: archive_checksum.(archive_key),
            else: {:ok, published}),
       :ok <-
         (if published not in [nil, ""] and checksum != published,
            do: {:error, {:checksum_mismatch, published, checksum}},
            else: :ok),
       {:ok, manifests} <- stored_manifests.(prefix),
       # A release entry with no manifests advertises a version whose
       # Package.swift the read frontend cannot serve, so the version would
       # resolve and then fail. Leaving it absent is the better state.
       :ok <- (if manifests == [], do: {:error, :no_stored_manifests}, else: :ok) do
    if apply? do
      lock_key = {:package, scope, name}

      case Lock.try_acquire(lock_key, 60) do
        {:ok, :acquired} ->
          try do
            # Re-read under the lock: the live sync may have written this package
            # between the check above and here.
            {:ok, current} = Metadata.get_package(scope, name)

            if Map.has_key?(Map.get(current, "releases", %{}) || %{}, version) do
              {:skip, :already_present}
            else
              updated =
                current
                |> Map.update("releases", %{version => %{"checksum" => checksum, "manifests" => manifests}}, fn releases ->
                  Map.put(releases || %{}, version, %{"checksum" => checksum, "manifests" => manifests})
                end)
                |> Map.update("skipped_releases", %{}, &Map.delete(&1 || %{}, version))

              case Metadata.put_package(scope, name, updated) do
                :ok -> {:ok, "restored checksum=#{String.slice(checksum, 0, 12)} manifests=#{length(manifests)}"}
                {:error, reason} -> {:error, reason}
              end
            end
          after
            Lock.release(lock_key)
          end

        {:error, :already_locked} ->
          {:skip, :package_locked}
      end
    else
      {:ok, "would restore checksum=#{String.slice(checksum, 0, 12)} manifests=#{length(manifests)}"}
    end
  else
    true -> {:skip, :already_present}
    {:skip, reason} -> {:skip, reason}
    # No catalog document at all, so there is no entry to restore. Creating one
    # is a different operation with different risks and is left to the sync.
    {:error, :not_found} -> {:skip, :no_catalog_document}
    {:error, reason} -> {:error, reason}
  end
end

regenerate = fn entry ->
  %{scope: scope, name: name, version: version} = entry

  case Metadata.get_package(scope, name) do
    {:ok, metadata} ->
      case Map.get(metadata, "repository_full_handle") do
        handle when is_binary(handle) and handle != "" ->
          if apply? do
            case Registry.force_resync_swift_package_version(handle, version, allow_checksum_change: true) do
              {:ok, job} -> {:ok, "enqueued job=#{job.id} handle=#{handle}"}
              {:error, reason} -> {:error, reason}
            end
          else
            {:ok, "would enqueue handle=#{handle}"}
          end

        _ ->
          {:error, :no_repository_handle}
      end

    {:error, reason} ->
      {:error, reason}
  end
end

{:ok, log} = File.open(log_path, [:append, :raw])

outcomes =
  Enum.reduce(entries, %{}, fn entry, acc ->
    result =
      try do
        case mode do
          "catalog_restore" -> restore_catalog_entry.(entry)
          "regenerate" -> regenerate.(entry)
        end
      rescue
        error -> {:error, Exception.message(error)}
      end

    {tag, detail} =
      case result do
        {:ok, detail} -> {:ok, detail}
        {:skip, reason} -> {:skip, to_string(reason)}
        {:error, reason} -> {:error, inspect(reason)}
      end

    # Dry runs are not recorded, so the same input can be applied afterwards.
    if apply?, do: IO.binwrite(log, [entry.ident, "\t", to_string(tag), "\t", detail, "\n"])

    if tag != :ok or rem(map_size(acc), 1) == 0 do
      IO.puts("  #{String.pad_trailing(to_string(tag), 6)} #{entry.ident}  #{detail}")
    end

    Map.update(acc, tag, 1, &(&1 + 1))
  end)

File.close(log)
IO.inspect(outcomes, label: "\noutcomes")

unless apply? do
  IO.puts("\ndry run — re-run with REPAIR_APPLY=1 to write")
end
