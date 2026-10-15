defmodule Tuist.BuildEntities.ProducersTest do
  # Enables the `:build_entities` flag for real. Flag records and their cache
  # are shared across test modules, so this module must not run async.
  use TuistTestSupport.Cases.DataCase, async: false
  use Mimic

  alias Once.Events.V1.ActionCompleted
  alias Once.Events.V1.ContentRef
  alias Once.Events.V1.RunCompleted
  alias Once.Events.V1.RunEvent
  alias Once.Events.V1.TargetInstance
  alias Once.Events.V1.TargetQueued
  alias Tuist.BuildEntities
  alias Tuist.BuildEntities.Identity
  alias Tuist.BuildEntities.Observation
  alias Tuist.ClickHouseRepo
  alias Tuist.FeatureFlags
  alias Tuist.Gradle
  alias Tuist.IngestRepo
  alias Tuist.Mix
  alias Tuist.OnceEvents
  alias Tuist.OnceEvents.Projector
  alias Tuist.OnceEvents.Run
  alias Tuist.OnceEvents.TargetInstance, as: TargetInstanceMapping
  alias Tuist.OnceEvents.Workers.ExpireStaleRunsWorker
  alias Tuist.Repo
  alias Tuist.Xcode
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.CommandEventsFixtures
  alias TuistTestSupport.Fixtures.GradleFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  setup do
    user = AccountsFixtures.user_fixture(preload: [:account])
    project = ProjectsFixtures.project_fixture(account_id: user.account.id)
    FunWithFlags.enable(:build_entities, for_actor: project)
    assert FeatureFlags.build_entities_enabled?(project)

    disabled = ProjectsFixtures.project_fixture(account_id: user.account.id)
    refute FeatureFlags.build_entities_enabled?(disabled)

    now = DateTime.utc_now()
    window = [start_datetime: DateTime.add(now, -1, :day), end_datetime: DateTime.add(now, 2, :hour)]
    %{project: project, disabled: disabled, account: user.account, window: window}
  end

  # Physical rows, without FINAL, so a duplicate write would be visible until a
  # background merge collapses it.
  defp stored_observations(project) do
    {:ok, %{rows: [[count]]}} =
      ClickHouseRepo.query(
        "SELECT count() FROM build_entity_observations WHERE project_id = {project_id:Int64}",
        %{project_id: project.id}
      )

    count
  end

  # Counts synchronous observation inserts, failing the first `failures`
  # attempts the way an unavailable ClickHouse would. Other inserts pass through.
  defp observation_inserts(failures \\ 0) do
    counters = :counters.new(2, [])

    stub(IngestRepo, :insert_all, fn
      Observation, rows, opts ->
        assert opts[:timeout] == 5_000
        assert opts[:settings] == [async_insert: 0, max_execution_time: 5]
        :counters.add(counters, 1, 1)
        if :counters.get(counters, 1) <= failures, do: raise("ClickHouse unavailable")
        result = Mimic.call_original(IngestRepo, :insert_all, [Observation, rows, opts])
        :counters.add(counters, 2, 1)
        result

      schema, rows, opts ->
        Mimic.call_original(IngestRepo, :insert_all, [schema, rows, opts])
    end)

    fn -> %{attempts: :counters.get(counters, 1), written: :counters.get(counters, 2)} end
  end

  defp kill_switch_on do
    stub(FunWithFlags, :enabled?, fn
      :build_entities_kill_switch -> true
      flag -> Mimic.call_original(FunWithFlags, :enabled?, [flag])
    end)
  end

  defp published_at(run), do: Repo.get!(Run, run.id).build_entities_published_at

  defp history(project, system, kind, identity, window) do
    id = Identity.id(project.id, system, kind, identity)
    {observations, _meta} = BuildEntities.history(project.id, system, kind, id, window)
    observations
  end

  defp project_event(run, kind, payload) do
    epoch_ms = System.system_time(:millisecond) - 60_000
    Projector.project(%RunEvent{epoch_ms: epoch_ms, payload: {kind, payload}}, run.project_id, run.run_id)
  end

  defp completed_action(target_execution_id, attrs \\ %{}) do
    struct(
      ActionCompleted,
      Map.merge(
        %{
          target_execution_id: target_execution_id,
          capability: "build",
          action_index: 0,
          identifier: "compile",
          result: :TARGET_RESULT_SUCCEEDED,
          duration_ms: 50,
          cache_key: "abc"
        },
        attrs
      )
    )
  end

  describe "Gradle tasks" do
    test "keep legacy reports as distinct entities and collapse retried builds", %{
      project: project,
      account: account,
      window: window
    } do
      build_id = UUIDv7.generate()

      tasks = [
        %{
          task_path: ":app:compileJava",
          outcome: "executed",
          cacheable: true,
          remote_cache_miss: true,
          duration_ms: 120,
          execution: %{build_path: ":", task_type: "JavaCompile"}
        },
        %{task_path: ":app:jar", outcome: "executed", cacheable: true, execution: %{build_path: ":", task_type: "Jar"}},
        %{
          task_path: ":app:javadoc",
          outcome: "executed",
          cacheable: true,
          duration_ms: 30,
          execution: %{build_path: ":", task_type: "Javadoc", remote_cache_lookup_outcome: "miss"}
        },
        %{
          task_path: ":app:lint",
          outcome: "executed",
          cacheable: true,
          duration_ms: 20,
          execution: %{build_path: ":", task_type: "Lint", remote_cache_lookup_outcome: "error"}
        },
        %{
          task_path: ":app:processResources",
          outcome: "up_to_date",
          duration_ms: 3,
          execution: %{build_path: ":", task_type: "Copy"}
        },
        %{task_path: ":app:compileJava", outcome: "remote_hit", duration_ms: 5},
        %{task_path: ":app:test", outcome: "failed", duration_ms: 50, execution: %{build_path: ":", task_type: "Test"}}
      ]

      attrs = [
        id: build_id,
        project_id: project.id,
        account_id: account.id,
        tasks: tasks,
        root_project_name: "app",
        git_branch: "main",
        is_ci: true
      ]

      GradleFixtures.build_fixture(attrs)
      GradleFixtures.build_fixture(attrs)

      current = %{
        "root_project_name" => "app",
        "build_path" => ":",
        "task_path" => ":app:compileJava",
        "task_type" => "JavaCompile"
      }

      legacy = %{current | "build_path" => "", "task_type" => ""}

      assert [%{cache_status: "miss", status: "success", duration_ms: 120, git_branch: "main", is_ci: true} = observation] =
               history(project, :gradle, "task", current, window)

      assert observation.parent_id == build_id
      assert [%{cache_status: "hit_remote", duration_ms: nil}] = history(project, :gradle, "task", legacy, window)

      # Executed without a recorded remote lookup is not a cache miss, and a
      # missing duration is not zero.
      assert [%{cache_status: "none", duration_ms: nil, status: "success"}] =
               history(project, :gradle, "task", %{current | "task_path" => ":app:jar", "task_type" => "Jar"}, window)

      assert [%{cache_status: "miss", duration_ms: 30}] =
               history(
                 project,
                 :gradle,
                 "task",
                 %{current | "task_path" => ":app:javadoc", "task_type" => "Javadoc"},
                 window
               )

      assert [%{cache_status: "none", duration_ms: 20}] =
               history(project, :gradle, "task", %{current | "task_path" => ":app:lint", "task_type" => "Lint"}, window)

      assert [%{status: "up_to_date", cache_status: "none", duration_ms: nil}] =
               history(
                 project,
                 :gradle,
                 "task",
                 %{current | "task_path" => ":app:processResources", "task_type" => "Copy"},
                 window
               )

      assert [%{status: "failure", cache_status: "none", duration_ms: 50}] =
               history(project, :gradle, "task", %{current | "task_path" => ":app:test", "task_type" => "Test"}, window)

      {entries, _meta} = BuildEntities.list(project.id, :gradle, "task", window)

      assert entries |> Enum.map(& &1.name) |> Enum.sort() ==
               [
                 ":app:compileJava",
                 ":app:compileJava",
                 ":app:jar",
                 ":app:javadoc",
                 ":app:lint",
                 ":app:processResources",
                 ":app:test"
               ]
    end
  end

  describe "Mix files and modules" do
    test "modules carry their file's compilation duration", %{project: project, account: account, window: window} do
      {:ok, build_id} =
        Mix.create_build(%{
          id: UUIDv7.generate(),
          project_id: project.id,
          account_id: account.id,
          duration_ms: 500,
          status: "success",
          git_branch: "main",
          files: [
            %{path: "lib/a.ex", modules: ["A", "A.Nested"], compile_duration_ms: 40, start_offset_ms: 10},
            %{path: "lib/b.ex", modules: ["B"], compile_duration_ms: 70},
            %{path: "lib/c.ex", modules: ["C"]}
          ]
        })

      assert [%{duration_ms: 40, parent_id: ^build_id, cache_status: "none", status: "success"}] =
               history(project, :mix, "file", %{"path" => "lib/a.ex"}, window)

      assert [%{duration_ms: 40}] = history(project, :mix, "module", %{"module" => "A.Nested"}, window)
      assert [%{duration_ms: 70}] = history(project, :mix, "module", %{"module" => "B"}, window)
      assert [%{duration_ms: nil}] = history(project, :mix, "file", %{"path" => "lib/c.ex"}, window)

      {modules, _meta} = BuildEntities.list(project.id, :mix, "module", window ++ [sort_by: "name", sort_order: "asc"])
      assert Enum.map(modules, & &1.name) == ["A", "A.Nested", "B", "C"]
    end
  end

  describe "Xcode generated-project modules" do
    test "observes targets with module cache metadata only", %{project: project, window: window} do
      event =
        CommandEventsFixtures.command_event_fixture(
          project_id: project.id,
          name: "generate",
          is_ci: true,
          git_branch: "main"
        )

      Xcode.create_xcode_graph(%{
        command_event: event,
        xcode_graph: %{
          name: "Graph",
          projects: [
            %{
              "name" => "App",
              "path" => ".",
              "targets" => [
                %{
                  "name" => "Core",
                  "binary_cache_metadata" => %{"hash" => "h1", "hit" => "remote", "build_duration" => 900}
                },
                %{"name" => "Feature", "binary_cache_metadata" => %{"hash" => "h2", "hit" => "miss"}},
                %{"name" => "AppTests", "selective_testing_metadata" => %{"hash" => "t1", "hit" => "local"}}
              ]
            }
          ]
        }
      })

      assert [
               %{cache_status: "hit_remote", is_ci: true, git_branch: "main", duration_ms: nil, status: "unknown"} =
                 observation
             ] =
               history(project, :xcode, "module", %{"project" => "App", "target" => "Core"}, window)

      assert observation.parent_id == event.id

      assert [%{cache_status: "miss"}] =
               history(project, :xcode, "module", %{"project" => "App", "target" => "Feature"}, window)

      {entries, _meta} = BuildEntities.list(project.id, :xcode, "module", window)
      assert entries |> Enum.map(& &1.name) |> Enum.sort() == ["Core", "Feature"]
    end
  end

  describe "rollout flag" do
    test "is off by default: native Gradle, Mix and Xcode ingestion is unchanged and nothing is observed", %{
      disabled: project,
      account: account,
      window: window
    } do
      build_id =
        GradleFixtures.build_fixture(
          project_id: project.id,
          account_id: account.id,
          root_project_name: "app",
          tasks: [%{task_path: ":app:jar", outcome: "executed", execution: %{build_path: ":", task_type: "Jar"}}]
        )

      assert {:ok, %{id: ^build_id}} = Gradle.get_build(build_id, project_id: project.id)

      {:ok, mix_build_id} =
        Mix.create_build(%{
          id: UUIDv7.generate(),
          project_id: project.id,
          account_id: account.id,
          duration_ms: 500,
          status: "success",
          files: [%{path: "lib/a.ex", modules: ["A"], compile_duration_ms: 40}]
        })

      assert {:ok, %{id: ^mix_build_id}} = Mix.get_build(mix_build_id, project.id)

      event = CommandEventsFixtures.command_event_fixture(project_id: project.id, name: "generate")

      Xcode.create_xcode_graph(%{
        command_event: event,
        xcode_graph: %{
          name: "Graph",
          projects: [
            %{
              "name" => "App",
              "path" => ".",
              "targets" => [%{"name" => "Core", "binary_cache_metadata" => %{"hash" => "h1", "hit" => "remote"}}]
            }
          ]
        }
      })

      assert {:ok, %{rows: [[targets]]}} =
               ClickHouseRepo.query(
                 "SELECT count() FROM xcode_targets WHERE project_id = {project_id:Int64}",
                 %{project_id: project.id}
               )

      assert targets > 0

      assert stored_observations(project) == 0

      for {system, kind} <- [{:gradle, "task"}, {:mix, "file"}, {:mix, "module"}, {:xcode, "module"}] do
        assert {[], %{total_count: 0}} = BuildEntities.list(project.id, system, kind, window)
      end
    end

    test "is per project: direct observation writes for a project that has not opted in are dropped", %{
      project: project,
      disabled: disabled
    } do
      observation = fn project_id ->
        %{
          project_id: project_id,
          system: :mix,
          kind: "file",
          identity: %{"path" => "lib/a.ex"},
          name: "lib/a.ex",
          parent_id: UUIDv7.generate(),
          observed_at: DateTime.utc_now()
        }
      end

      assert :ok = BuildEntities.record([observation.(project.id), observation.(disabled.id)])
      assert stored_observations(project) == 1
      assert stored_observations(disabled) == 0
      assert :disabled = BuildEntities.record([observation.(disabled.id)], sync: true)
      assert stored_observations(disabled) == 0
    end

    test "the kill switch stops observation writes for opted-in projects", %{
      project: project,
      account: account
    } do
      kill_switch_on()
      refute FeatureFlags.build_entities_enabled?(project)

      build_id =
        GradleFixtures.build_fixture(
          project_id: project.id,
          account_id: account.id,
          tasks: [%{task_path: ":app:jar", outcome: "executed", execution: %{build_path: ":", task_type: "Jar"}}]
        )

      assert {:ok, %{id: ^build_id}} = Gradle.get_build(build_id, project_id: project.id)
      assert stored_observations(project) == 0
    end
  end

  describe "Once actions" do
    setup %{project: project} do
      {:ok, run} = OnceEvents.upsert_run(%{project_id: project.id, run_id: UUIDv7.generate()})
      %{run: run}
    end

    test "attribute actions to their declared slot, skip unmapped actions and publish the run once", %{
      project: project,
      run: run,
      window: window
    } do
      inserts = observation_inserts()
      project_event(run, :target_instance, %TargetInstance{target_instance_id: "instance-1", target_id: "//app:lib"})

      project_event(run, :target_queued, %TargetQueued{
        target_execution_id: "execution-1",
        target_instance_id: "instance-1"
      })

      project_event(run, :action_completed, completed_action("execution-1"))
      project_event(run, :action_completed, completed_action("execution-1", %{action_index: 1, was_cached: true}))
      project_event(run, :action_completed, completed_action("unmapped"))
      project_event(run, :run_completed, %RunCompleted{result: 1})

      published_at = published_at(run)
      assert %DateTime{} = published_at

      # A replayed RunCompleted and later sweeps neither republish nor move the marker.
      project_event(run, :run_completed, %RunCompleted{result: 1})
      assert {:ok, 0} = OnceEvents.publish_recent_build_entities()
      assert published_at(run) == published_at
      assert %{attempts: 1, written: 1} = inserts.()
      assert stored_observations(project) == 2

      slot = %{"target_id" => "//app:lib", "capability" => "build", "action_index" => "0"}

      assert [%{status: "success", cache_status: "none", duration_ms: 50} = observation] =
               history(project, :once, "action", slot, window)

      assert observation.parent_id == run.run_id
      assert [%{cache_status: "hit"}] = history(project, :once, "action", %{slot | "action_index" => "1"}, window)

      {entries, _meta} = BuildEntities.list(project.id, :once, "action", window)
      assert length(entries) == 2
    end

    test "runs with no actions or no target mappings are marked published without a write", %{
      project: project,
      run: run
    } do
      inserts = observation_inserts()
      {:ok, empty} = OnceEvents.upsert_run(%{project_id: project.id, run_id: UUIDv7.generate()})
      project_event(empty, :run_completed, %RunCompleted{result: 1})

      project_event(run, :action_completed, completed_action("unmapped"))
      project_event(run, :run_completed, %RunCompleted{result: 1})

      for published <- [empty, run], do: assert(%DateTime{} = published_at(published))

      project_event(run, :run_completed, %RunCompleted{result: 1})
      assert {:ok, 0} = OnceEvents.publish_recent_build_entities()
      assert %{attempts: 0} = inserts.()
      assert stored_observations(project) == 0
    end

    test "a transient ClickHouse failure at RunCompleted leaves the run unpublished until recovery writes it once", %{
      project: project,
      run: run,
      window: window
    } do
      inserts = observation_inserts(1)
      project_event(run, :target_instance, %TargetInstance{target_instance_id: "instance", target_id: "//app:lib"})
      project_event(run, :target_queued, %TargetQueued{target_execution_id: "execution", target_instance_id: "instance"})
      project_event(run, :action_completed, completed_action("execution"))

      assert_raise RuntimeError, "ClickHouse unavailable", fn ->
        project_event(run, :run_completed, %RunCompleted{result: 1})
      end

      assert %{finalization: "finalized", build_entities_published_at: nil} = Repo.get!(Run, run.id)
      assert stored_observations(project) == 0

      assert {:ok, 1} = OnceEvents.publish_recent_build_entities()
      published_at = published_at(run)
      assert %DateTime{} = published_at

      project_event(run, :run_completed, %RunCompleted{result: 1})
      assert {:ok, 0} = OnceEvents.publish_recent_build_entities()
      assert published_at(run) == published_at
      assert %{attempts: 2, written: 1} = inserts.()
      assert stored_observations(project) == 1

      slot = %{"target_id" => "//app:lib", "capability" => "build", "action_index" => "0"}
      assert [%{status: "success"}] = history(project, :once, "action", slot, window)
    end

    test "the stale-run worker publishes abandoned runs once, retrying after a failed write", %{
      project: project,
      run: run,
      window: window
    } do
      inserts = observation_inserts(1)
      project_event(run, :target_instance, %TargetInstance{target_instance_id: "instance", target_id: "//app:lib"})
      project_event(run, :target_queued, %TargetQueued{target_execution_id: "execution", target_instance_id: "instance"})
      project_event(run, :action_completed, completed_action("execution"))
      project_event(run, :action_completed, completed_action("unmapped"))
      project_event(run, :action_completed, completed_action("execution", %{capability: "_phase"}))
      Repo.update!(Ecto.Changeset.change(run, heartbeat_at: DateTime.add(DateTime.utc_now(), -7_200, :second)))

      slot = %{"target_id" => "//app:lib", "capability" => "build", "action_index" => "0"}
      assert [] == history(project, :once, "action", slot, window)
      assert_raise RuntimeError, "ClickHouse unavailable", fn -> ExpireStaleRunsWorker.perform(%{}) end
      assert %{finalization: "lost", build_entities_published_at: nil} = Repo.get!(Run, run.id)

      assert :ok = ExpireStaleRunsWorker.perform(%{})
      assert %DateTime{} = published_at(run)

      assert [%{parent_id: parent_id, status: "success", duration_ms: 50}] =
               history(project, :once, "action", slot, window)

      assert parent_id == run.run_id

      assert :ok = ExpireStaleRunsWorker.perform(%{})
      assert {:ok, 0} = OnceEvents.publish_recent_build_entities()
      assert %{attempts: 2, written: 1} = inserts.()
      assert stored_observations(project) == 1
      assert {[%{observations: 1}], _meta} = BuildEntities.list(project.id, :once, "action", window)
    end

    test "recent recovery uses stable batches, publishes only unpublished runs and excludes active and old ones", %{
      project: project,
      run: run
    } do
      at = DateTime.add(DateTime.utc_now(), -60, :second)

      rows =
        for _ <- 1..101 do
          %{
            id: UUIDv7.generate(),
            project_id: project.id,
            run_id: UUIDv7.generate(),
            finalization: "finalized",
            started_at: at,
            finalized_at: at,
            inserted_at: at,
            updated_at: at
          }
        end

      Repo.insert_all(Run, rows)
      {:ok, old} = OnceEvents.upsert_run(%{project_id: project.id, run_id: UUIDv7.generate()})
      {:ok, _} = OnceEvents.finalize_run(old, %{finalized_at: DateTime.add(at, -7_200, :second)})
      {:ok, future} = OnceEvents.upsert_run(%{project_id: project.id, run_id: UUIDv7.generate()})
      {:ok, _} = OnceEvents.finalize_run(future, %{finalized_at: DateTime.add(at, 600, :second)})

      assert {:ok, 101} = OnceEvents.publish_recent_build_entities()

      ids = Enum.map(rows, & &1.id)

      published = from(r in Run, where: r.id in ^ids and not is_nil(r.build_entities_published_at))
      assert Repo.aggregate(published, :count) == 101

      for skipped <- [run, old, future], do: assert(is_nil(published_at(skipped)))
      assert %{finalization: "active"} = OnceEvents.get_run(project.id, run.run_id)

      assert {:ok, 0} = OnceEvents.publish_recent_build_entities()
    end

    test "a project that has not opted in stores no target mappings, observations or publication marker", %{
      disabled: project
    } do
      inserts = observation_inserts()
      {:ok, run} = OnceEvents.upsert_run(%{project_id: project.id, run_id: UUIDv7.generate()})
      assert :ok = project_event(run, :target_instance, %TargetInstance{target_instance_id: "i", target_id: "//app:lib"})
      assert :ok = project_event(run, :target_queued, %TargetQueued{target_execution_id: "e", target_instance_id: "i"})
      assert :ok = project_event(run, :action_completed, completed_action("e"))
      assert :ok = project_event(run, :run_completed, %RunCompleted{result: 1})

      assert %{finalization: "finalized", build_entities_published_at: nil} = Repo.get!(Run, run.id)
      assert Repo.aggregate(from(m in TargetInstanceMapping, where: m.once_run_id == ^run.id), :count) == 0
      assert {:ok, false} = OnceEvents.publish_build_entities(run)
      assert {:ok, 0} = OnceEvents.publish_recent_build_entities()
      assert %{attempts: 0} = inserts.()
      assert stored_observations(project) == 0
    end

    test "the kill switch stops target mappings and publication for an opted-in project", %{run: run} do
      kill_switch_on()
      inserts = observation_inserts()
      assert :ok = project_event(run, :target_instance, %TargetInstance{target_instance_id: "i", target_id: "//app:lib"})
      assert :ok = project_event(run, :action_completed, completed_action("e"))
      assert :ok = project_event(run, :run_completed, %RunCompleted{result: 1})

      assert is_nil(published_at(run))
      assert Repo.aggregate(from(m in TargetInstanceMapping, where: m.once_run_id == ^run.id), :count) == 0
      assert {:ok, 0} = OnceEvents.publish_recent_build_entities()
      assert %{attempts: 0} = inserts.()
    end

    test "skip mappings the tables cannot store without failing the event stream", %{
      project: project,
      run: run,
      window: window
    } do
      # 1024 characters but 2048 bytes: `varchar` limits count characters.
      exact_target = String.duplicate("é", 1024)

      instances = [
        %TargetInstance{target_instance_id: "oversized-target", target_id: String.duplicate("t", 1025)},
        %TargetInstance{target_instance_id: String.duplicate("i", 513), target_id: "//app:lib"},
        %TargetInstance{target_instance_id: "nul", target_id: "//app:" <> <<0>>},
        %TargetInstance{
          target_instance_id: "exact",
          target_id: exact_target,
          configuration_digest: %ContentRef{digest: :binary.copy(<<0xFF>>, 129)}
        }
      ]

      for instance <- instances, do: assert(:ok = project_event(run, :target_instance, instance))

      executions = [
        %TargetQueued{target_execution_id: "execution-oversized-target", target_instance_id: "oversized-target"},
        %TargetQueued{target_execution_id: "execution-nul", target_instance_id: "nul"},
        %TargetQueued{target_execution_id: "execution-exact", target_instance_id: "exact"},
        %TargetQueued{target_execution_id: "execution-attempt", target_instance_id: "exact", attempt: 2_147_483_648},
        %TargetQueued{target_execution_id: String.duplicate("e", 513), target_instance_id: "exact"}
      ]

      for execution <- executions, do: assert(:ok = project_event(run, :target_queued, execution))

      for execution <- ["execution-oversized-target", "execution-nul", "execution-exact", "execution-attempt"] do
        assert :ok = project_event(run, :action_completed, completed_action(execution))
      end

      assert :ok = project_event(run, :run_completed, %RunCompleted{result: 1})
      assert %{finalization: "finalized"} = OnceEvents.get_run(project.id, run.run_id)

      # The 258-character hex digest does not fit, so it is left out rather than truncated.
      assert %{target_id: ^exact_target, configuration_digest: nil} =
               Repo.get_by(TargetInstanceMapping, once_run_id: run.id, target_instance_id: "exact")

      # Only the exact mapping attributes an action. The out-of-range attempt
      # skipped its mapping instead of defaulting, so that action stays unattributed.
      slot = %{"target_id" => exact_target, "capability" => "build", "action_index" => "0"}
      assert [_observation] = history(project, :once, "action", slot, window)
      assert {[%{identity: ^slot}], _meta} = BuildEntities.list(project.id, :once, "action", window)
    end
  end
end
