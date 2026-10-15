defmodule Tuist.BuildEntities.ProducersTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Once.Events.V1.ActionCompleted
  alias Once.Events.V1.ContentRef
  alias Once.Events.V1.RunCompleted
  alias Once.Events.V1.RunEvent
  alias Once.Events.V1.TargetInstance
  alias Once.Events.V1.TargetQueued
  alias Tuist.BuildEntities
  alias Tuist.BuildEntities.Identity
  alias Tuist.ClickHouseRepo
  alias Tuist.Mix
  alias Tuist.OnceEvents
  alias Tuist.OnceEvents.Projector
  alias Tuist.OnceEvents.Run
  alias Tuist.OnceEvents.TargetInstance, as: TargetInstanceMapping
  alias Tuist.OnceEvents.Workers.ExpireStaleRunsWorker
  alias Tuist.ReapiCache
  alias Tuist.Repo
  alias Tuist.Xcode
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.CommandEventsFixtures
  alias TuistTestSupport.Fixtures.GradleFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures

  setup do
    user = AccountsFixtures.user_fixture(preload: [:account])
    project = ProjectsFixtures.project_fixture(account_id: user.account.id)
    now = DateTime.utc_now()
    window = [start_datetime: DateTime.add(now, -1, :day), end_datetime: DateTime.add(now, 2, :hour)]
    %{project: project, account: user.account, window: window}
  end

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

  describe "Xcode cache actions" do
    test "are keyed by the exact cache key and report the cache operation duration", %{
      project: project,
      window: window
    } do
      {:ok, build} =
        RunsFixtures.build_fixture(
          project_id: project.id,
          git_branch: "main",
          cacheable_tasks: [
            %{type: :swift, status: :hit_remote, key: "0~a", read_duration: 12.4, description: "Compile A.swift"},
            %{type: :clang, status: :miss, key: "0~b", write_duration: 3.0}
          ]
        )

      assert [%{cache_status: "hit_remote", duration_ms: 12, status: "unknown"} = observation] =
               history(project, :xcode, "cache_action", %{"type" => "swift", "key" => "0~a"}, window)

      assert observation.parent_id == build.id

      assert [%{cache_status: "miss", duration_ms: 3}] =
               history(project, :xcode, "cache_action", %{"type" => "clang", "key" => "0~b"}, window)

      {entries, _meta} =
        BuildEntities.list(project.id, :xcode, "cache_action", window ++ [sort_by: "name", sort_order: "asc"])

      assert Enum.map(entries, & &1.name) == ["0~b", "Compile A.swift"]
    end
  end

  describe "Bazel cache actions" do
    test "observe action cache lookups and writes once, even when Kura resends a batch", %{
      project: project,
      window: window
    } do
      event = fn attrs ->
        Map.merge(
          %{
            event_id: UUIDv7.generate(),
            client_kind: "bazel",
            operation: "action_cache",
            outcome: "hit",
            action_digest: "digest",
            size: 42,
            duration_us: 2_000,
            invocation_id: "invocation-1",
            action_mnemonic: "CppCompile",
            target_label: "//:app",
            configuration_id: "config",
            project_id: project.id,
            account_handle: "account",
            project_handle: "project",
            cache_endpoint: "cache.tuist.dev"
          },
          attrs
        )
      end

      events = [
        event.(%{}),
        event.(%{outcome: "miss"}),
        event.(%{outcome: "write"}),
        event.(%{operation: "cas", action_digest: "blob"})
      ]

      ReapiCache.create_cache_events(events)
      ReapiCache.create_cache_events(events)

      identity = %{"action_digest_hash" => "digest", "action_mnemonic" => "CppCompile", "target_label" => "//:app"}
      observations = history(project, :bazel, "cache_action", identity, window)

      assert observations |> Enum.map(& &1.cache_status) |> Enum.sort() == ["hit_remote", "miss", "write"]
      assert Enum.all?(observations, &(&1.parent_id == "invocation-1" and &1.duration_ms == 2 and is_nil(&1.is_ci)))

      assert {[%{name: "CppCompile //:app", identity: ^identity, observations: 3}], _meta} =
               BuildEntities.list(project.id, :bazel, "cache_action", window)

      id = Identity.id(project.id, :bazel, "cache_action", identity)
      analytics = BuildEntities.analytics(project.id, :bazel, "cache_action", id, window)
      assert %{observations: 3, hits: 1, misses: 1, hit_rate: 50.0} = analytics.total
    end

    test "keep native ingestion for events without an event ID but do not observe them", %{
      project: project,
      window: window
    } do
      legacy = %{
        client_kind: "bazel",
        operation: "action_cache",
        outcome: "hit",
        action_digest: "legacy-digest",
        size: 42,
        duration_us: 2_000,
        invocation_id: "invocation-legacy",
        action_mnemonic: "CppCompile",
        target_label: "//:legacy",
        configuration_id: "config",
        project_id: project.id,
        account_handle: "account",
        project_handle: "project",
        cache_endpoint: "cache.tuist.dev"
      }

      ReapiCache.create_cache_events([legacy])
      ReapiCache.create_cache_events([legacy])

      assert {:ok, %{rows: [[2]]}} =
               ClickHouseRepo.query(
                 "SELECT count() FROM reapi_cache_events WHERE project_id = {project_id:Int64} AND action_digest = 'legacy-digest'",
                 %{project_id: project.id}
               )

      identity = %{
        "action_digest_hash" => "legacy-digest",
        "action_mnemonic" => "CppCompile",
        "target_label" => "//:legacy"
      }

      assert [] == history(project, :bazel, "cache_action", identity, window)
      assert {[], _meta} = BuildEntities.list(project.id, :bazel, "cache_action", window)
    end

    test "ingest non-UUID event IDs under a fresh row ID without observing them", %{project: project, window: window} do
      event = fn attrs ->
        Map.merge(
          %{
            client_kind: "bazel",
            operation: "action_cache",
            outcome: "hit",
            size: 42,
            duration_us: 2_000,
            invocation_id: "invocation-ids",
            action_mnemonic: "CppCompile",
            configuration_id: "config",
            project_id: project.id,
            account_handle: "account",
            project_handle: "project",
            cache_endpoint: "cache.tuist.dev"
          },
          attrs
        )
      end

      producer_id = UUIDv7.generate()

      ReapiCache.create_cache_events([
        event.(%{event_id: "kura-event-1", action_digest: "string-id-digest", target_label: "//:string"}),
        event.(%{event_id: producer_id, action_digest: "uuid-id-digest", target_label: "//:uuid"})
      ])

      assert {:ok, %{rows: rows}} =
               ClickHouseRepo.query(
                 """
                 SELECT action_digest, toString(id)
                 FROM reapi_cache_events
                 WHERE project_id = {project_id:Int64} AND invocation_id = 'invocation-ids'
                 """,
                 %{project_id: project.id}
               )

      assert length(rows) == 2
      ids = Map.new(rows, fn [digest, id] -> {digest, id} end)
      assert ids["uuid-id-digest"] == producer_id
      assert {:ok, _} = Ecto.UUID.cast(ids["string-id-digest"])

      string_identity = %{
        "action_digest_hash" => "string-id-digest",
        "action_mnemonic" => "CppCompile",
        "target_label" => "//:string"
      }

      uuid_identity = %{string_identity | "action_digest_hash" => "uuid-id-digest", "target_label" => "//:uuid"}

      assert [] == history(project, :bazel, "cache_action", string_identity, window)
      assert [%{execution_id: ^producer_id}] = history(project, :bazel, "cache_action", uuid_identity, window)
    end
  end

  describe "Once actions" do
    setup %{project: project} do
      {:ok, run} = OnceEvents.upsert_run(%{project_id: project.id, run_id: UUIDv7.generate()})
      %{run: run}
    end

    test "attribute actions to their declared slot and skip actions without a target mapping", %{
      project: project,
      run: run,
      window: window
    } do
      project_event(run, :target_instance, %TargetInstance{target_instance_id: "instance-1", target_id: "//app:lib"})

      project_event(run, :target_queued, %TargetQueued{
        target_execution_id: "execution-1",
        target_instance_id: "instance-1"
      })

      project_event(run, :action_completed, completed_action("execution-1"))
      project_event(run, :action_completed, completed_action("execution-1", %{action_index: 1, was_cached: true}))
      project_event(run, :action_completed, completed_action("unmapped"))
      project_event(run, :run_completed, %RunCompleted{result: 1})
      project_event(run, :run_completed, %RunCompleted{result: 1})

      slot = %{"target_id" => "//app:lib", "capability" => "build", "action_index" => "0"}

      assert [%{status: "success", cache_status: "none", duration_ms: 50} = observation] =
               history(project, :once, "action", slot, window)

      assert observation.parent_id == run.run_id
      assert [%{cache_status: "hit"}] = history(project, :once, "action", %{slot | "action_index" => "1"}, window)

      {entries, _meta} = BuildEntities.list(project.id, :once, "action", window)
      assert length(entries) == 2
    end

    test "the stale-run worker indexes completed actions even without RunCompleted", %{
      project: project,
      run: run,
      window: window
    } do
      project_event(run, :target_instance, %TargetInstance{target_instance_id: "instance", target_id: "//app:lib"})
      project_event(run, :target_queued, %TargetQueued{target_execution_id: "execution", target_instance_id: "instance"})
      project_event(run, :action_completed, completed_action("execution"))
      project_event(run, :action_completed, completed_action("unmapped"))
      project_event(run, :action_completed, completed_action("execution", %{capability: "_phase"}))
      Repo.update!(Ecto.Changeset.change(run, heartbeat_at: DateTime.add(DateTime.utc_now(), -7_200, :second)))

      slot = %{"target_id" => "//app:lib", "capability" => "build", "action_index" => "0"}
      assert [] == history(project, :once, "action", slot, window)
      expect(BuildEntities, :record, fn _ -> raise "unavailable observation store" end)
      assert_raise RuntimeError, "unavailable observation store", fn -> ExpireStaleRunsWorker.perform(%{}) end
      assert %{finalization: "lost"} = OnceEvents.get_run(project.id, run.run_id)
      stub(BuildEntities, :record, fn observations -> Mimic.call_original(BuildEntities, :record, [observations]) end)
      assert :ok = ExpireStaleRunsWorker.perform(%{})

      assert [%{parent_id: parent_id, status: "success", duration_ms: 50}] =
               history(project, :once, "action", slot, window)

      assert parent_id == run.run_id

      assert :ok = ExpireStaleRunsWorker.perform(%{})
      assert {[%{observations: 1}], _meta} = BuildEntities.list(project.id, :once, "action", window)
    end

    test "recent recovery repairs failed finalization emission without acknowledging the failure", %{
      project: project,
      run: run,
      window: window
    } do
      project_event(run, :target_instance, %TargetInstance{target_instance_id: "instance", target_id: "//app:lib"})
      project_event(run, :target_queued, %TargetQueued{target_execution_id: "execution", target_instance_id: "instance"})
      project_event(run, :action_completed, completed_action("execution"))
      expect(BuildEntities, :record, fn _ -> raise "unavailable observation store" end)

      assert_raise RuntimeError, "unavailable observation store", fn ->
        project_event(run, :run_completed, %RunCompleted{result: 1})
      end

      assert %{finalization: "finalized"} = OnceEvents.get_run(project.id, run.run_id)
      stub(BuildEntities, :record, fn observations -> Mimic.call_original(BuildEntities, :record, [observations]) end)
      assert :ok = ExpireStaleRunsWorker.perform(%{})
      slot = %{"target_id" => "//app:lib", "capability" => "build", "action_index" => "0"}
      assert [%{status: "success"}] = history(project, :once, "action", slot, window)
    end

    test "recent recovery uses stable batches and excludes active and old terminal runs", %{
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
      expect(BuildEntities, :record, 101, fn [] -> :ok end)

      assert {:ok, 101} = OnceEvents.publish_recent_build_entities()
      assert %{finalization: "active"} = OnceEvents.get_run(project.id, run.run_id)
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
