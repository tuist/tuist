defmodule Tuist.BuildEntities.Producers do
  @moduledoc """
  Maps native ingestion payloads to build entity observations.

  Producers derive identities from existing native report fields, without a
  new client payload contract or catalog lookups. Once stages target mappings
  from its existing protocol and resolves action slots in one query at run
  finalization. Other producers map the native rows already held in memory.

  Observation IDs are deterministic (`Tuist.BuildEntities.Identity`) within a
  native parent, so resending the same build/run/event identity does not double
  count. Once actions without target mappings remain accepted but cannot
  create retry-safe observations.

  Only recorded facts are mapped: an outcome the producer does not recognize
  becomes `"unknown"`, a cache miss is only a miss the toolchain reported, and a
  missing duration stays `nil` rather than zero.
  """

  alias Tuist.BuildEntities

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
  BEP action executions, not profile intervals or cache RPCs. Target, mnemonic
  and configured primary output identify a logical action across builds; the
  output retains Bazel's configuration prefix rather than merging configurations.
  Execution start distinguishes repeated attempts in one invocation. Older Kura
  payloads without this identity remain accepted but unindexed. Missing end-time
  evidence stays untimed, and a measured zero remains zero.
  """
  def bazel_actions(project, actions) do
    actions
    |> Enum.flat_map(fn action ->
      with target when is_binary(target) and byte_size(target) in 1..1024 <- action["target_label"],
           mnemonic when is_binary(mnemonic) and byte_size(mnemonic) in 1..128 <- action["mnemonic"],
           started when is_integer(started) and started > 0 <- action["started_at_ms"],
           {:ok, observed_at} <- DateTime.from_unix(started, :millisecond) do
        output = action["primary_output"]

        [
          %{
            project_id: project.id,
            system: :bazel,
            kind: "action",
            identity: %{"target_label" => target, "mnemonic" => mnemonic, "primary_output" => output},
            name: "#{mnemonic} #{Path.basename(output)}",
            parent_id: action["invocation_id"],
            discriminator: started,
            execution_id: Integer.to_string(started),
            status: if(action["success"], do: "success", else: "failure"),
            cache_status: "none",
            duration_ms: integer_or_nil(action["duration_ms"]),
            observed_at: observed_at,
            git_branch: optional_string(action["git_branch"]),
            git_commit_sha: optional_string(action["git_commit_sha"]),
            is_ci: if(is_boolean(action["is_ci"]), do: action["is_ci"])
          }
        ]
      else
        _ -> []
      end
    end)
    |> BuildEntities.record()
  end

  defp optional_string(value) when is_binary(value) and byte_size(value) <= 512, do: value
  defp optional_string(_), do: nil

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

  @doc """
  Xcode targets with measured compilation work from an activity log. They share
  the graph's project/target identity, but refer to the native build rather than
  a command event. The execution reference distinguishes these sources without
  treating a cache resolution as another compilation sample.

  Activity logs report zero compilation time for targets that compiled no
  sources. Omit those targets rather than pricing incremental no-work builds as
  zero-cost compilations. Missing target outcomes remain unknown.
  """
  def xcode_build(build, targets) do
    targets
    |> Enum.filter(fn target ->
      Map.get(target, :project) not in [nil, ""] and Map.get(target, :name) not in [nil, ""] and
        is_integer(Map.get(target, :compilation_duration)) and target.compilation_duration > 0
    end)
    |> with_ordinals(&[&1.project, &1.name])
    |> Enum.map(fn {target, ordinal} ->
      %{
        project_id: build.project_id,
        system: :xcode,
        kind: "module",
        identity: %{"project" => target.project, "target" => target.name},
        name: target.name,
        parent_id: build.id,
        discriminator: "compilation:#{ordinal}",
        execution_id: "build_target:#{ordinal}",
        status: xcode_build_status(Map.get(target, :status)),
        cache_status: "none",
        duration_ms: target.compilation_duration,
        git_branch: build.git_branch,
        git_commit_sha: build.git_commit_sha,
        is_ci: build.is_ci,
        observed_at: build.started_at || build.inserted_at
      }
    end)
    |> BuildEntities.record()
  end

  defp xcode_build_status(status) when status in [:success, "success"], do: "success"
  defp xcode_build_status(status) when status in [:failure, "failure"], do: "failure"
  defp xcode_build_status(_status), do: "unknown"

  # `XcodeTarget.changeset/5` stores the hit as its Enum8 integer, and records a
  # target with module cache metadata but no hit as a miss.
  defp xcode_module_cache_status(0), do: "miss"
  defp xcode_module_cache_status(1), do: "hit_local"
  defp xcode_module_cache_status(2), do: "hit_remote"
  defp xcode_module_cache_status(_hit), do: "none"

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
  def once_run(run, actions, opts \\ []) do
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
    |> BuildEntities.record(opts)
  end

  defp once_status("succeeded"), do: "success"
  defp once_status(result) when result in ["failed", "timed_out", "infrastructure_error"], do: "failure"
  defp once_status("skipped"), do: "skipped"
  defp once_status("cancelled"), do: "cancelled"
  defp once_status(_result), do: "unknown"

  defp integer_or_nil(value) when is_integer(value) and value >= 0, do: value
  defp integer_or_nil(_value), do: nil

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
