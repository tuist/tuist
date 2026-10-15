defmodule Tuist.BuildEntities.Producers do
  @moduledoc """
  Maps native ingestion payloads to build entity observations.

  Producers derive identities from existing native report fields, without a
  new client payload contract or catalog lookups. Once stages target mappings
  from its existing protocol and resolves action slots in one query at run
  finalization. Other producers map the native rows already held in memory.

  Observation IDs are deterministic (`Tuist.BuildEntities.Identity`) within a
  native parent, so resending the same build/run/event identity does not double
  count. Legacy Kura events without a producer UUID and Once actions without
  target mappings remain accepted but cannot create retry-safe observations.

  Only recorded facts are mapped: an outcome the producer does not recognize
  becomes `"unknown"`, a cache miss is only a miss the toolchain reported, and a
  missing duration stays `nil` rather than zero.
  """

  alias Tuist.BuildEntities
  alias Tuist.ReapiCache

  @doc """
  Gradle tasks from a build report, given the `gradle_builds` row and pairs of
  each reported task with the `gradle_tasks` row inserted for it. Identity is
  root project, build path, task path and task type, the same key the task
  analytics page groups by. Reports from plugins that predate
  `execution.build_path` or `task_type` keep empty values, which form distinct
  entities rather than guessing `":"`.

  Durations are kept for executed work only (`executed` and `failed`); hit,
  skipped, up-to-date and no-source timings are not execution durations.
  """
  def gradle_build(build, tasks) do
    tasks
    |> with_ordinals(fn {_task, entry} -> [entry.build_path, entry.task_path, entry.task_type] end)
    |> Enum.map(fn {{task, entry}, ordinal} ->
      outcome = to_string(entry.outcome)

      %{
        project_id: build.project_id,
        system: :gradle,
        kind: "task",
        identity: %{
          "root_project_name" => build.root_project_name,
          "build_path" => entry.build_path,
          "task_path" => entry.task_path,
          "task_type" => entry.task_type
        },
        name: entry.task_path,
        parent_id: build.id,
        discriminator: ordinal,
        execution_id: entry.id,
        status: gradle_status(outcome),
        cache_status: gradle_cache_status(outcome, remote_cache_miss?(entry)),
        duration_ms: if(outcome in ["executed", "failed"], do: integer_or_nil(Map.get(task, :duration_ms))),
        git_branch: build.git_branch,
        git_commit_sha: build.git_commit_sha,
        is_ci: build.is_ci,
        observed_at: entry.started_at || build.started_at || build.inserted_at
      }
    end)
    |> BuildEntities.record()
  end

  defp gradle_status(outcome) when outcome in ["executed", "local_hit", "remote_hit", "cache_hit"], do: "success"
  defp gradle_status("failed"), do: "failure"
  defp gradle_status("skipped"), do: "skipped"
  defp gradle_status("up_to_date"), do: "up_to_date"
  defp gradle_status("no_source"), do: "no_source"
  defp gradle_status(_outcome), do: "unknown"

  # Only a recorded remote lookup miss is a miss. Executing a cacheable task, a
  # lookup error, or no lookup at all is not.
  defp remote_cache_miss?(entry), do: entry.remote_cache_miss == true or entry.remote_cache_lookup_outcome == "miss"

  defp gradle_cache_status("local_hit", _remote_cache_miss), do: "hit_local"
  defp gradle_cache_status("remote_hit", _remote_cache_miss), do: "hit_remote"
  # `FROM-CACHE` without a known origin.
  defp gradle_cache_status("cache_hit", _remote_cache_miss), do: "hit"
  defp gradle_cache_status(_outcome, true), do: "miss"
  defp gradle_cache_status(_outcome, _remote_cache_miss), do: "none"

  @doc """
  Mix compiled files and the modules they define, given the build row and
  pairs of each reported file with the `mix_compiled_files` row inserted for
  it. Module observations carry the defining file's compilation duration: Mix
  reports compilation per file, so a module has no independently measured
  duration. Files only compiled successfully when the build did; otherwise the
  outcome is unknown.
  """
  def mix_build(build, files) do
    base = %{
      project_id: build.project_id,
      system: :mix,
      parent_id: build.id,
      status: if(build.status == "success", do: "success", else: "unknown"),
      cache_status: "none",
      git_branch: build.git_branch,
      git_commit_sha: build.git_commit_sha,
      is_ci: build.is_ci
    }

    files =
      files
      |> Enum.reject(fn {_file, row} -> row.path == "" end)
      |> Enum.map(fn {file, row} ->
        duration_ms = integer_or_nil(Map.get(file, :compile_duration_ms, Map.get(file, "compile_duration_ms")))
        {row, duration_ms, offset_datetime(build.started_at, row.start_offset_ms) || build.inserted_at}
      end)

    file_observations =
      files
      |> with_ordinals(fn {row, _duration_ms, _observed_at} -> [row.path] end)
      |> Enum.map(fn {{row, duration_ms, observed_at}, ordinal} ->
        Map.merge(base, %{
          kind: "file",
          identity: %{"path" => row.path},
          name: row.path,
          discriminator: ordinal,
          execution_id: row.id,
          duration_ms: duration_ms,
          observed_at: observed_at
        })
      end)

    module_observations =
      files
      |> Enum.flat_map(fn {row, _, _} = file -> row.modules |> Enum.reject(&(&1 == "")) |> Enum.map(&{&1, file}) end)
      |> with_ordinals(fn {module, _file} -> [module] end)
      |> Enum.map(fn {{module, {row, duration_ms, observed_at}}, ordinal} ->
        Map.merge(base, %{
          kind: "module",
          identity: %{"module" => module},
          name: module,
          discriminator: ordinal,
          execution_id: row.id,
          duration_ms: duration_ms,
          observed_at: observed_at
        })
      end)

    BuildEntities.record(file_observations ++ module_observations)
  end

  defp offset_datetime(%DateTime{} = started_at, offset_ms) when is_integer(offset_ms),
    do: DateTime.add(started_at, offset_ms, :millisecond)

  defp offset_datetime(%NaiveDateTime{} = started_at, offset_ms) when is_integer(offset_ms),
    do: NaiveDateTime.add(started_at, offset_ms, :millisecond)

  defp offset_datetime(_started_at, _offset_ms), do: nil

  @doc """
  Generated-project modules from a `tuist generate` or `tuist cache` graph.
  Only targets with module (binary) cache metadata are observed. Identity is
  the Xcode project name and target name.

  The reported `build_duration` is the binary's recorded compilation time, not
  the duration of this resolution, so observations carry no duration.
  """
  def xcode_graph(command_event, projects, targets) do
    project_names = Map.new(projects, &{&1.id, &1.name || ""})

    targets
    |> Enum.reject(&is_nil(&1.binary_cache_hash))
    |> with_ordinals(&[Map.get(project_names, &1.xcode_project_id, ""), &1.name])
    |> Enum.map(fn {target, ordinal} ->
      %{
        project_id: command_event.project_id,
        system: :xcode,
        kind: "module",
        identity: %{"project" => Map.get(project_names, target.xcode_project_id, ""), "target" => target.name},
        name: target.name,
        parent_id: command_event.id,
        discriminator: ordinal,
        execution_id: target.id,
        status: "unknown",
        cache_status: xcode_module_cache_status(target.binary_cache_hit),
        git_branch: Map.get(command_event, :git_branch),
        git_commit_sha: Map.get(command_event, :git_commit_sha),
        is_ci: Map.get(command_event, :is_ci),
        observed_at: Map.get(command_event, :ran_at) || target.inserted_at
      }
    end)
    |> BuildEntities.record()
  end

  # `XcodeTarget.changeset/5` stores the hit as its Enum8 integer, and records a
  # target with module cache metadata but no hit as a miss.
  defp xcode_module_cache_status(0), do: "miss"
  defp xcode_module_cache_status(1), do: "hit_local"
  defp xcode_module_cache_status(2), do: "hit_remote"
  defp xcode_module_cache_status(_hit), do: "none"

  @doc """
  Xcode compilation cache actions from a build. Xcode reports no target, file
  or other stable logical identity for a cache key, so the identity is the
  exact cache key: an entity is one key's history (miss, then local or remote
  hits), not a logical compile step across input changes. Descriptions are
  display names only and never grouped.

  `duration_ms` is the cache operation duration in milliseconds: the read for
  hits and the write for misses. The compilation outcome is not reported.
  """
  def xcode_build(build, cacheable_tasks) do
    cacheable_tasks
    |> with_ordinals(&[to_string(&1.type), &1.key])
    |> Enum.map(fn {task, ordinal} ->
      status = to_string(task.status)

      %{
        project_id: build.project_id,
        system: :xcode,
        kind: "cache_action",
        identity: %{"type" => to_string(task.type), "key" => task.key},
        name: task.description || task.key,
        parent_id: build.id,
        discriminator: ordinal,
        execution_id: task.key,
        status: "unknown",
        cache_status: if(status in ["hit_local", "hit_remote", "miss"], do: status, else: "none"),
        duration_ms: if(status == "miss", do: task.write_duration, else: task.read_duration),
        git_branch: build.git_branch,
        git_commit_sha: build.git_commit_sha,
        is_ci: build.is_ci,
        observed_at: build.inserted_at
      }
    end)
    |> BuildEntities.record()
  end

  @doc """
  Bazel action cache operations reported by Kura: lookups (`hit`, `miss`) and
  recorded result writes (`write`). Identity is the exact REAPI action digest
  hash plus the mnemonic and target label the client declared for it. A write
  is its own observation because it is not guaranteed to follow a reported
  miss. CAS transfers are excluded.

  Cache events carry no branch, commit or environment, so those stay empty, and
  no execution outcome, so the status is unknown.

  Takes the reported events and the native rows inserted for them, in order.
  Only events whose native row reuses a valid producer UUID `event_id` are
  observed. Older Kura nodes omit it, and the webhook accepts any string, so
  such events get a server-minted row ID that changes on every retry: deriving
  observations from them would double count and link to rows that do not
  exist. Those events keep their native ingestion and are simply not observed.
  """
  def bazel_cache_events(events, entries) do
    events
    |> Enum.zip(entries)
    |> Enum.filter(fn {event, entry} -> ReapiCache.producer_event_id(event) == {:ok, entry.id} end)
    |> Enum.map(&elem(&1, 1))
    |> Enum.filter(&(to_string(&1.operation) == "action_cache" and to_string(&1.outcome) in ["hit", "miss", "write"]))
    |> Enum.map(fn event ->
      mnemonic = event.action_mnemonic || ""
      label = event.target_label || ""

      %{
        project_id: event.project_id,
        system: :bazel,
        kind: "cache_action",
        identity: %{
          "action_digest_hash" => event.action_digest,
          "action_mnemonic" => mnemonic,
          "target_label" => label
        },
        name: [mnemonic, label] |> Enum.reject(&(&1 == "")) |> Enum.join(" ") |> non_empty(event.action_digest),
        parent_id: event.invocation_id,
        discriminator: event.id,
        execution_id: event.id,
        status: "unknown",
        cache_status: bazel_cache_status(to_string(event.outcome)),
        duration_ms: event.duration_ms,
        observed_at: event.observed_at
      }
    end)
    |> BuildEntities.record()
  end

  defp bazel_cache_status("hit"), do: "hit_remote"
  defp bazel_cache_status("miss"), do: "miss"
  defp bazel_cache_status("write"), do: "write"

  @doc """
  Once actions of a finished run, attributed to their declared slot: the
  target ID, capability and zero-based declaration index. The `identifier` is
  a diagnostic label and does not take part, so reordering a target's declared
  actions changes their identities. Actions whose target mapping was never
  reported are skipped. The parent is the client run ID, which the run page
  resolves within the project.

  Once reports whether an action was served from cache, not whether a lookup
  missed, so uncached actions have no cache status.
  """
  def once_run(run, actions) do
    actions
    |> Enum.reject(&(is_nil(&1.target_id) or &1.target_id == "" or &1.capability == "_phase"))
    |> Enum.map(fn action ->
      %{
        project_id: run.project_id,
        system: :once,
        kind: "action",
        identity: %{
          "target_id" => action.target_id,
          "capability" => action.capability,
          "action_index" => Integer.to_string(action.action_index)
        },
        name:
          action.display_name || action.identifier || "#{action.target_id} #{action.capability} ##{action.action_index}",
        parent_id: run.run_id,
        discriminator: action.target_execution_id,
        execution_id: action.id,
        status: once_status(action.result),
        cache_status: if(action.was_cached, do: "hit", else: "none"),
        duration_ms: action.duration_ms,
        git_branch: run.git_branch,
        git_commit_sha: run.git_rev,
        is_ci: run.is_ci,
        observed_at: action.started_at || action.finished_at
      }
    end)
    |> BuildEntities.record()
  end

  defp once_status("succeeded"), do: "success"
  defp once_status(result) when result in ["failed", "timed_out", "infrastructure_error"], do: "failure"
  defp once_status("skipped"), do: "skipped"
  defp once_status("cancelled"), do: "cancelled"
  defp once_status(_result), do: "unknown"

  defp integer_or_nil(value) when is_integer(value) and value >= 0, do: value
  defp integer_or_nil(_value), do: nil

  defp non_empty("", fallback), do: fallback
  defp non_empty(value, _fallback), do: value

  # Pairs each item with its occurrence index among items sharing the same
  # identity, in payload order, so repeated executions within one parent get
  # distinct but deterministic observation IDs.
  defp with_ordinals(items, identity_fun) do
    items
    |> Enum.map_reduce(%{}, fn item, seen ->
      key = identity_fun.(item)
      ordinal = Map.get(seen, key, 0)
      {{item, ordinal}, Map.put(seen, key, ordinal + 1)}
    end)
    |> elem(0)
  end
end
