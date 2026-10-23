# Synthetic, bounded inventory data for local UI previews, never production measurements.
# Run with: mix run priv/repo/seed_build_inventories.exs
import Ecto.Query

alias Tuist.Accounts
alias Tuist.Bazel
alias Tuist.Bazel.Action, as: BazelAction
alias Tuist.Bazel.Invocation
alias Tuist.BuildEntities
alias Tuist.BuildEntities.Identity
alias Tuist.BuildEntities.Observation
alias Tuist.Builds
alias Tuist.Builds.Build
alias Tuist.Builds.BuildTarget
alias Tuist.ClickHouseRepo
alias Tuist.CommandEvents
alias Tuist.CommandEvents.Event
alias Tuist.Gradle
alias Tuist.Gradle.Build, as: GradleBuild
alias Tuist.Gradle.Task, as: GradleTask
alias Tuist.IngestRepo
alias Tuist.Mix, as: MixBuilds
alias Tuist.Mix.Build, as: MixBuild
alias Tuist.Mix.CompiledFile
alias Tuist.OnceEvents
alias Tuist.Projects
alias Tuist.Projects.Project
alias Tuist.ReapiCache
alias Tuist.Repo
alias Tuist.Xcode
alias Tuist.Xcode.XcodeGraph

if Mix.env() != :dev, do: raise("Build inventory seeds are only supported in development")

for repo <- [Repo, IngestRepo] do
  database = repo.config()[:database] || ""

  if !String.starts_with?(database, "tuist_development_") do
    raise "Build inventory seeds require an isolated tuist_development_* database, got #{inspect(database)}"
  end
end

defmodule BuildInventoryDemoSeeds do
  @moduledoc false
  @samples 28
  @tag "synthetic-inventory-demo-v2"

  def run do
    user =
      case Accounts.get_user_by_email("tuistrocks@tuist.dev") do
        {:ok, user} ->
          user

        {:error, :not_found} ->
          {:ok, user} =
            Accounts.create_user("tuistrocks@tuist.dev",
              password: "tuistrocks",
              confirmed_at: NaiveDateTime.utc_now(),
              setup_billing: false
            )

          user
      end

    user = Repo.preload(user, :account)

    user
    |> Accounts.User.password_changeset(%{password: "tuistrocks", password_confirmation: "tuistrocks"})
    |> Repo.update!()

    projects =
      Map.new([:xcode, :gradle, :once, :mix, :bazel], fn system ->
        name = "inventory-#{system}"

        project =
          Repo.get_by(Project, account_id: user.account.id, name: name) ||
            Projects.create_project!(%{name: name, account: %{id: user.account.id}},
              build_system: system,
              visibility: :public
            )

        FunWithFlags.enable(:build_entities, for_actor: project)
        {system, project}
      end)

    now = DateTime.utc_now()

    for {system, project} <- projects, sample <- 1..@samples do
      started_at = DateTime.add(now, -(@samples - sample + 1) * 21_600, :second)
      is_ci = rem(sample, 3) != 0
      id = Identity.observation_id(@tag, to_string(project.id), to_string(sample))

      attrs = %{
        id: id,
        project_id: project.id,
        account_id: user.account.id,
        account_handle: user.account.name,
        started_at: started_at,
        inserted_at: DateTime.to_naive(started_at),
        status: "success",
        is_ci: is_ci,
        git_branch: if(rem(sample, 5) == 0, do: "demo/feature", else: "main"),
        git_commit_sha: :sha |> :crypto.hash("#{@tag}:#{sample}") |> Base.encode16(case: :lower),
        custom_tags: [@tag],
        custom_values: %{"data_source" => "Synthetic UI preview, not real build measurements"}
      }

      seed_build(system, attrs, sample)
    end

    flush_buffers()
    seed_untimed_xcode(projects.xcode, now)
    seed_default_branch_graphs(projects.xcode, user, now)
    flush_buffers()
    print_links(projects, user.account.name)
    IO.puts("Synthetic preview only. Login: tuistrocks@tuist.dev / tuistrocks")
  end

  defp seed_build(:bazel, attrs, sample) do
    if !ClickHouseRepo.exists?(
         from(i in Invocation, where: i.project_id == ^attrs.project_id and i.invocation_id == ^attrs.id)
       ) do
      elapsed = 30_000 + sample * 1200

      invocation = %{
        invocation_id: attrs.id,
        project_id: attrs.project_id,
        account_handle: attrs.account_handle,
        project_handle: "inventory-bazel",
        command: if(rem(sample, 4) == 0, do: "test", else: "build"),
        target_patterns: ["//demo:all"],
        status: if(rem(sample, 9) == 0, do: "failure", else: "success"),
        exit_code: if(rem(sample, 9) == 0, do: 1, else: 0),
        started_at: attrs.started_at |> DateTime.to_naive() |> NaiveDateTime.truncate(:second),
        finished_at:
          attrs.started_at
          |> DateTime.add(elapsed, :millisecond)
          |> DateTime.to_naive()
          |> NaiveDateTime.truncate(:second),
        duration_ms: elapsed,
        is_ci: attrs.is_ci,
        git_branch: attrs.git_branch,
        git_commit_sha: attrs.git_commit_sha,
        custom_values: attrs.custom_values,
        bazel_version: "8.4.2",
        cache_endpoint: "http://localhost:8397",
        actions_created: 20,
        actions_executed: 5 + rem(sample, 4),
        targets_configured: 10,
        packages_loaded: 4
      }

      Bazel.create_invocations([invocation])

      ReapiCache.create_cache_events(
        for index <- 0..19 do
          %{
            event_id: Identity.observation_id(@tag, attrs.id, "cache:#{index}"),
            client_kind: "bazel",
            operation: "action_cache",
            outcome: if(rem(sample + index, 5) == 0, do: "miss", else: "hit"),
            action_digest:
              :sha256 |> :crypto.hash("#{@tag}:bazel:#{rem(sample, 3)}:#{index}") |> Base.encode16(case: :lower),
            size: 200 + index * 100,
            duration_ms: 1 + rem(sample + index, 20),
            invocation_id: attrs.id,
            action_mnemonic: "CppCompile",
            target_label: "//demo:#{target_name(index)}",
            configuration_id: "demo-debug",
            project_id: attrs.project_id,
            account_handle: attrs.account_handle,
            project_handle: "inventory-bazel",
            cache_endpoint: invocation.cache_endpoint,
            observed_at: DateTime.add(attrs.started_at, index, :second)
          }
        end
      )
    end

    seed_bazel_actions(attrs, sample)
  end

  defp seed_build(:xcode, attrs, sample) do
    if !exists?(Build, attrs) do
      targets =
        for index <- 0..26 do
          duration = duration(sample, index, attrs.is_ci, 180)

          %{
            name: target_name(index),
            project: "InventoryDemo",
            build_duration: duration + 250,
            compilation_duration: duration,
            status: "success"
          }
        end

      {:ok, _} =
        attrs
        |> Map.merge(%{
          duration: Enum.sum(Enum.map(targets, & &1.build_duration)),
          scheme: "InventoryDemo",
          configuration: "Debug",
          category: "incremental",
          macos_version: "26.0",
          xcode_version: "26.0",
          model_identifier: "Mac15,6",
          targets: targets
        })
        |> Builds.create_build()
    end
  end

  defp seed_build(:gradle, attrs, sample) do
    if !exists?(GradleBuild, attrs) do
      tasks =
        for index <- 0..28 do
          outcome = task_outcome(sample, index)

          %{
            task_path: if(index == 27, do: ":cached:compileKotlin", else: ":#{target_name(index)}:compileKotlin"),
            outcome: outcome,
            cacheable: true,
            duration_ms:
              if(outcome not in ["executed", "failed"] or index == 28,
                do: 0,
                else: duration(sample, index, attrs.is_ci, 130)
              ),
            execution: %{build_path: ":", task_type: "KotlinCompile"}
          }
        end

      {:ok, _} =
        attrs
        |> Map.merge(%{
          root_project_name: "InventoryDemo",
          status: if(Enum.any?(tasks, &(&1.outcome == "failed")), do: "failure", else: "success"),
          duration_ms: Enum.sum(Enum.map(tasks, & &1.duration_ms)),
          gradle_version: "9.0",
          java_version: "21",
          requested_tasks: [":AppCore:compileKotlin"],
          tasks: tasks
        })
        |> Gradle.create_build()
    end
  end

  defp seed_build(:mix, attrs, sample) do
    if !exists?(MixBuild, attrs) do
      files =
        for index <- 0..28 do
          elapsed = if(index == 28, do: 0, else: duration(sample, index, attrs.is_ci, 25))

          file = %{
            path: "lib/inventory_demo/#{Macro.underscore(target_name(index))}.ex",
            modules:
              if(index == 0,
                do: ["InventoryDemo.AppCore", "InventoryDemo.AppCore.Helpers"],
                else: ["InventoryDemo.#{target_name(index)}"]
              ),
            start_offset_ms: index * 10
          }

          if index == 27, do: file, else: Map.put(file, :compile_duration_ms, elapsed)
        end

      {:ok, _} =
        attrs
        |> Map.merge(%{duration_ms: 30_000, elixir_version: "1.19", otp_version: "28", mix_env: "dev", files: files})
        |> MixBuilds.create_build()
    end
  end

  defp seed_build(:once, attrs, sample) do
    {:ok, run} =
      OnceEvents.upsert_run(%{
        project_id: attrs.project_id,
        account_id: attrs.account_id,
        run_id: attrs.id,
        started_at: attrs.started_at,
        is_ci: attrs.is_ci,
        git_branch: attrs.git_branch,
        git_rev: attrs.git_commit_sha,
        command_display: "once build //demo:all (synthetic demo)",
        host_class: "synthetic-inventory-demo"
      })

    if is_nil(run.build_entities_published_at) do
      for index <- 0..28 do
        target_id = "//demo:#{Macro.underscore(target_name(index))}"
        instance = "instance-#{index}"
        execution = "execution-#{index}"
        result = action_result(sample, index)
        cached? = cached_action?(sample, index, result)
        elapsed = if(cached? or result == "skipped" or index == 28, do: 0, else: duration(sample, index, attrs.is_ci, 95))

        :ok = OnceEvents.ingest_target_instance(run, %{target_instance_id: instance, target_id: target_id})
        :ok = OnceEvents.ingest_target_execution(run, %{target_execution_id: execution, target_instance_id: instance})

        {:ok, _} =
          OnceEvents.ingest_action(run, %{
            target_execution_id: execution,
            capability: "build",
            action_index: 0,
            display_name: "Build #{target_name(index)}",
            result: result,
            was_cached: cached?,
            duration_ms: elapsed,
            started_at: attrs.started_at,
            finished_at: DateTime.add(attrs.started_at, elapsed, :millisecond)
          })
      end

      {:ok, run} =
        OnceEvents.finalize_run(run, %{
          exit_status: if(rem(sample, 9) == 0, do: 1, else: 0),
          wall_ms: 90_000,
          finalized_at: DateTime.add(attrs.started_at, 90, :second)
        })

      {:ok, _} = OnceEvents.publish_build_entities(run)
    end
  end

  defp seed_bazel_actions(attrs, sample) do
    if !ClickHouseRepo.exists?(
         from(o in Observation,
           where:
             o.project_id == ^attrs.project_id and o.system == "bazel" and o.kind == "action" and o.parent_id == ^attrs.id
         )
       ) do
      started_at =
        ClickHouseRepo.one!(
          from(i in Invocation,
            where: i.project_id == ^attrs.project_id and i.invocation_id == ^attrs.id,
            order_by: [desc: i.inserted_at],
            select: i.started_at,
            limit: 1
          )
        )

      attrs = %{attrs | started_at: DateTime.from_naive!(started_at, "Etc/UTC")}

      :ok =
        BazelAction.ingest(%Project{id: attrs.project_id}, %{
          "actions" =>
            for index <- 0..29 do
              %{
                "invocation_id" => attrs.id,
                "target_label" => "//demo:#{target_name(div(index, 2))}",
                "mnemonic" => if(rem(index, 2) == 0, do: "CppCompile", else: "CppLink"),
                "primary_output" => "bazel-out/demo-debug/bin/demo/#{target_name(div(index, 2))}/Source#{index}.o",
                "started_at_ms" => DateTime.to_unix(attrs.started_at, :millisecond) + index * 1000,
                "duration_ms" => bazel_duration(sample, index, attrs.is_ci),
                "success" => !(rem(sample, 9) == 0 and rem(index, 7) == 0),
                "is_ci" => attrs.is_ci,
                "git_branch" => attrs.git_branch,
                "git_commit_sha" => attrs.git_commit_sha,
                "log" => "Synthetic preview action, not real build measurements",
                "log_truncated" => false
              }
            end
        })
    end
  end

  defp bazel_duration(_sample, 27, _is_ci), do: nil
  defp bazel_duration(_sample, 28, _is_ci), do: 0
  defp bazel_duration(sample, index, is_ci), do: duration(sample, index, is_ci, 120)

  defp task_outcome(sample, 2) when rem(sample, 9) == 0, do: "failed"
  defp task_outcome(_sample, 27), do: "remote_hit"
  defp task_outcome(sample, 26) when rem(sample, 2) == 0, do: "up_to_date"
  defp task_outcome(sample, 25) when rem(sample, 3) == 0, do: "skipped"
  defp task_outcome(sample, 24) when rem(sample, 4) == 0, do: "no_source"
  defp task_outcome(sample, index) when index < 27 and rem(sample + index, 7) == 0, do: "remote_hit"
  defp task_outcome(_sample, _index), do: "executed"

  defp action_result(sample, 2) when rem(sample, 9) == 0, do: "failed"
  defp action_result(sample, 26) when rem(sample, 2) == 0, do: "skipped"
  defp action_result(_sample, _index), do: "succeeded"

  defp cached_action?(sample, index, result),
    do: result == "succeeded" and (index == 27 or (index < 27 and rem(sample + index, 7) == 0))

  defp duration(sample, index, is_ci, scale) do
    base = (index + 1) * scale + rem(sample * 137 + index * 79, scale * 3)
    multiplier = if rem(sample + index, 13) == 0, do: 4, else: 1
    div(base * multiplier * if(is_ci, do: 10, else: 7), 10)
  end

  defp target_name(0), do: "AppCore"
  defp target_name(1), do: "Networking"
  defp target_name(2), do: "DesignSystem"
  defp target_name(27), do: "TimingNotRecorded"
  defp target_name(28), do: "MeasuredZero"
  defp target_name(index), do: "Feature#{String.pad_leading(to_string(index), 2, "0")}"

  defp exists?(schema, attrs) do
    ClickHouseRepo.exists?(from(b in schema, where: b.project_id == ^attrs.project_id and b.id == ^attrs.id))
  end

  defp flush_buffers do
    for buffer <- [
          BazelAction.Buffer,
          Build.Buffer,
          BuildTarget.Buffer,
          GradleBuild.Buffer,
          GradleTask.Buffer,
          MixBuild.Buffer,
          CompiledFile.Buffer,
          Event.Buffer,
          XcodeGraph.Buffer,
          Tuist.Xcode.XcodeProject.Buffer,
          Tuist.Xcode.XcodeTarget.Buffer,
          Observation.Buffer
        ] do
      buffer.flush()
    end
  end

  defp seed_untimed_xcode(project, now) do
    :ok =
      BuildEntities.record(
        [
          %{
            project_id: project.id,
            system: :xcode,
            kind: "module",
            identity: %{"project" => "InventoryDemo", "target" => "CachedOnly"},
            name: "CachedOnly",
            parent_id: "",
            discriminator: @tag,
            status: "unknown",
            cache_status: "hit_remote",
            observed_at: now,
            is_ci: true,
            git_branch: "main"
          }
        ],
        sync: true
      )
  end

  defp seed_default_branch_graphs(project, user, now) do
    for {snapshot, offset, count} <- [
          {"before-period", -8 * 86_400, 35},
          {"removed-modules", -3 * 86_400, 32},
          {"latest", -3600, 30}
        ] do
      id = Identity.observation_id(@tag, to_string(project.id), "default-branch-graph-v1:#{snapshot}")

      if !ClickHouseRepo.exists?(from(g in XcodeGraph, where: g.project_id == ^project.id and g.command_event_id == ^id)) do
        existing = ClickHouseRepo.one(from(e in Event, where: e.project_id == ^project.id and e.id == ^id))
        event = existing || create_graph_event(project, user, id, DateTime.add(now, offset, :second))

        {:ok, _} =
          Xcode.create_xcode_graph(%{
            command_event: event,
            xcode_graph: %{
              name: "Synthetic inventory preview: #{snapshot}",
              projects: [
                %{
                  "name" => "InventoryDemo",
                  "path" => "InventoryDemo.xcodeproj",
                  "targets" => Enum.map(0..(count - 1), &%{"name" => target_name(&1)})
                }
              ]
            }
          })
      end
    end
  end

  defp create_graph_event(project, user, id, ran_at) do
    {:ok, event} =
      CommandEvents.create_command_event(%{
        id: id,
        project_id: project.id,
        user_id: user.id,
        name: "generate",
        command_arguments: ["generate", "--no-open"],
        duration: 1500,
        client_id: @tag,
        tuist_version: "4.208.0",
        swift_version: "6.2",
        macos_version: "26.0",
        is_ci: true,
        status: :success,
        git_branch: project.default_branch,
        git_commit_sha: :sha |> :crypto.hash(id) |> Base.encode16(case: :lower),
        ran_at: ran_at,
        created_at: ran_at,
        cacheable_targets: [],
        local_cache_target_hits: [],
        remote_cache_target_hits: [],
        test_targets: [],
        local_test_target_hits: [],
        remote_test_target_hits: []
      })

    event
  end

  defp print_links(projects, account_handle) do
    base = System.fetch_env!("TUIST_SERVER_URL")

    window = [
      start_datetime: DateTime.add(DateTime.utc_now(), -30 * 86_400, :second),
      end_datetime: DateTime.utc_now(),
      page_size: 100,
      sort_by: "p90_duration_ms",
      sort_order: "desc"
    ]

    for resource <- BuildEntities.Resources.dashboard_resources() do
      project = Map.fetch!(projects, resource.system)
      {entries, meta} = BuildEntities.list(project.id, resource.system, resource.kind, window)
      true = meta.total_count >= 28
      if resource.key != :mix_modules, do: true = Enum.any?(entries, &is_number(&1.p90_duration_ms))
      path = "#{base}/#{account_handle}/#{project.name}#{resource.path}"
      IO.puts("#{resource.label}: #{path} (#{meta.total_count} entries)")
      IO.puts("  Example detail: #{path}/#{hd(entries).id}")
    end

    bazel = "#{base}/#{account_handle}/inventory-bazel"
    IO.puts("Bazel native overview: #{bazel}")
    IO.puts("Bazel build runs: #{bazel}/builds/build-runs")
    IO.puts("Bazel actions: #{bazel}/builds/bazel/actions?analytics-date-range=last-7-days")
    IO.puts("Bazel cache: #{bazel}/bazel-cache (separate cache analytics)")
  end
end

BuildInventoryDemoSeeds.run()
