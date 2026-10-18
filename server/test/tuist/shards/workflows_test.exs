defmodule Tuist.Shards.WorkflowsTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  import Ecto.Query

  alias Ecto.Changeset
  alias Tuist.ClickHouseRepo
  alias Tuist.FeatureFlags
  alias Tuist.IngestRepo
  alias Tuist.Repo
  alias Tuist.Shards
  alias Tuist.Shards.Workers.ProjectWorkflowWorker
  alias Tuist.Shards.Workflow
  alias Tuist.Shards.Workflows
  alias Tuist.Shards.WorkflowShard
  alias Tuist.Tests
  alias Tuist.Tests.Test
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  setup do
    stub(FeatureFlags, :postgres_shard_plans_enabled?, fn _ -> true end)
    %{project: ProjectsFixtures.project_fixture()}
  end

  test "plan and assignments survive absent ClickHouse rows and flag changes", %{project: project} do
    %{plan: plan} = create_plan(project)
    stub(FeatureFlags, :postgres_shard_plans_enabled?, fn _ -> false end)
    reject(ClickHouseRepo, :one, 1)
    reject(IngestRepo, :one, 1)
    reject(IngestRepo, :preload, 2)
    stub(Tuist.Storage, :object_exists?, fn _, _ -> false end)
    stub(Tuist.Storage, :generate_download_url, fn _, _ -> "https://example.com/bundle.zip" end)

    assert {:ok, loaded} = Shards.get_shard_plan(plan.id)
    assert loaded.authority == :postgres
    assert loaded.merged_test_run_id == plan.merged_test_run_id
    assert Enum.sort(Enum.map(loaded.modules, & &1.module_name)) == ["AppTests", "CoreTests"]

    assert {:ok, by_id} = Shards.get_shard_for_plan_id(project, project.account, plan.id, 0)
    assert {:ok, by_reference} = Shards.get_shard(project, project.account, plan.reference, 0)
    assert by_id == by_reference
    assert by_id.modules != []
  end

  test "suite assignments and catch-all use the persisted module inventory", %{project: project} do
    %{plan: plan} =
      create_plan(project, %{
        granularity: "suite",
        modules: ["AppTests", "CoreTests"],
        test_suites: ["AppTests/LoginSuite", "AppTests/SignupSuite"]
      })

    reject(IngestRepo, :preload, 2)
    stub(Tuist.Storage, :object_exists?, fn _, _ -> false end)
    stub(Tuist.Storage, :generate_download_url, fn _, _ -> "https://example.com/bundle.zip" end)

    assert {:ok, shard} =
             Shards.get_shard(project, project.account, plan.reference, 1, suite_catch_all?: true)

    assert shard.suites == %{}
    assert shard.modules == []
    assert shard.skip == ["AppTests/LoginSuite"]

    download_modules = plan.modules |> Enum.filter(&(&1.shard_index == 1)) |> Enum.map(& &1.module_name)
    assert Enum.sort(download_modules) == ["AppTests", "CoreTests"]
  end

  test "reference enrollment persists when the creation gate is disabled", %{project: project} do
    %{plan: first} = create_plan(project)
    stub(FeatureFlags, :postgres_shard_plans_enabled?, fn _ -> false end)
    %{plan: second} = create_plan(project)
    assert first.id != second.id
    assert second.authority == :postgres
    assert Workflows.get(second.id, project.id)

    %{plan: legacy} = create_plan(project, %{reference: "not-enrolled"})
    assert legacy.authority == :clickhouse
    refute Workflows.get(legacy.id)
  end

  test "plan, assignments and publication roll back together", %{project: project} do
    expect(Oban, :insert!, fn _ -> raise "publication failed" end)

    assert_raise RuntimeError, "publication failed", fn -> create_plan(project) end
    refute Repo.exists?(from(w in Workflow, where: w.project_id == ^project.id))
    refute Repo.exists?(WorkflowShard)
  end

  test "reports merge only PostgreSQL state and detail reads do not require publication", %{project: project} do
    %{plan: plan} = create_plan(project)
    stub(ClickHouseRepo, :one, fn _ -> nil end)

    assert {:ok, first} = report(project, plan, 0, scheme: "App", duration: 100)
    assert first.status == "in_progress"
    assert {:ok, second} = report(project, plan, 1, scheme: "", duration: 200)
    assert second.id == first.id
    assert second.id == plan.merged_test_run_id
    assert second.status == "success"
    assert second.scheme == "App"
    assert second.duration == 200
    assert NaiveDateTime.after?(second.inserted_at, first.inserted_at)

    assert {:ok, loaded} = Tests.get_test(second.id, preload: [:shard_plan])
    assert loaded.status == "success"
    assert loaded.shard_plan.authority == :postgres
    assert length(loaded.shard_plan.modules) == 2
    assert_enqueued(worker: ProjectWorkflowWorker, args: %{workflow_id: plan.id})
  end

  test "linked build IDs survive explicitly nil report fields", %{project: project} do
    build_id = Ecto.UUID.generate()
    gradle_id = Ecto.UUID.generate()
    %{plan: plan} = create_plan(project, %{build_run_id: build_id, gradle_build_id: gradle_id})
    assert {:ok, test} = report(project, plan, 0, build_run_id: nil, gradle_build_id: nil)
    assert test.build_run_id == build_id
    assert test.gradle_build_id == gradle_id
  end

  test "publication failure rolls back shard state and the snapshot", %{project: project} do
    %{plan: plan} = create_plan(project)
    expect(Oban, :insert!, fn _ -> raise "publication failed" end)
    assert_raise RuntimeError, "publication failed", fn -> report(project, plan, 0) end
    workflow = Workflows.get(plan.id)
    assert workflow.snapshot == nil
    assert workflow.version == 0
    assert Enum.all?(workflow.shards, &is_nil(&1.status))
  end

  test "publication versions advance even when the previous version is ahead of the database clock", %{project: project} do
    %{plan: plan} = create_plan(project)
    assert {:ok, _} = report(project, plan, 0)
    future = Workflows.get(plan.id).version + 1_000_000_000
    Repo.update_all(from(w in Workflow, where: w.id == ^plan.id), set: [version: future])
    assert {:ok, final} = report(project, plan, 1)
    assert Workflows.get(plan.id).version == future + 1
    expected_time = (future + 1) |> DateTime.from_unix!(:microsecond) |> DateTime.to_naive()
    assert final.inserted_at == expected_time
  end

  test "single-shard plans preserve processing and skipped statuses", %{project: project} do
    %{plan: plan} = create_plan(project, %{modules: ["AppTests"], shard_total: 1})
    assert {:ok, initial} = report(project, plan, 0, status: "processing", duration: 0)
    assert initial.status == "processing"
    assert {:ok, skipped} = report(project, plan, 0, status: "skipped")
    assert skipped.status == "skipped"
  end

  test "parsed facts inherit known metadata and repetition flakiness stays authoritative", %{project: project} do
    %{plan: plan} = create_plan(project)
    assert {:ok, _} = report(project, plan, 0, scheme: "App", status: "processing", is_ci: true)

    modules = [
      %{
        name: "AppTests",
        status: "success",
        duration: 100,
        test_cases: [
          %{
            name: "flaky",
            status: "success",
            duration: 100,
            repetitions: [%{status: "failure", duration: 50}, %{status: "success", duration: 50}]
          }
        ]
      }
    ]

    assert {:ok, parsed} = report(project, plan, 0, is_ci: true, test_modules: modules)
    assert parsed.is_flaky
    assert Enum.map(parsed.test_case_runs, & &1.scheme) == ["App"]
    assert {:ok, final} = report(project, plan, 1, is_ci: true)
    assert final.is_flaky
    assert Workflows.get_test(final.id).is_flaky
  end

  test "stress candidate facts are flushed before committing completion", %{project: project} do
    %{plan: plan} = create_plan(project)

    expect(Tuist.Tests.TestRunStressCandidate.Buffer, :flush, fn ->
      assert Workflows.get_test(plan.merged_test_run_id) == nil
      :ok
    end)

    assert {:ok, _} = report(project, plan, 0)
  end

  test "initial upload replay cannot roll a terminal shard back", %{project: project} do
    %{plan: plan} = create_plan(project)
    assert {:ok, _} = report(project, plan, 0, status: "failure", duration: 100)
    assert {:ok, _} = report(project, plan, 1)
    assert {:ok, replay} = report(project, plan, 0, status: "processing", duration: 0)
    assert replay.status == "failure"
    assert replay.duration == 100
    assert Repo.get_by!(WorkflowShard, workflow_id: plan.id, shard_index: 0).status == "failure"
  end

  test "a core-fact flush failure cannot commit completion", %{project: project} do
    %{plan: plan} = create_plan(project)
    stub(Tuist.Tests.TestModuleRun.Buffer, :flush, fn -> {:error, :unavailable} end)

    assert_raise MatchError, fn -> report(project, plan, 0) end
    assert Workflows.get(plan.id).snapshot == nil
    assert Enum.all?(Workflows.get(plan.id).shards, &is_nil(&1.status))
  end

  test "foreign projects and invalid shard indexes cannot change a workflow", %{project: project} do
    %{plan: plan} = create_plan(project)
    foreign = ProjectsFixtures.project_fixture()
    assert {:error, :not_found} = report(foreign, plan, 0)
    assert {:error, :invalid_shard_index} = report(project, plan, -1)
    assert {:error, :invalid_shard_index} = report(project, plan, plan.shard_count)
    assert Workflows.get(plan.id).snapshot == nil
  end

  test "uppercase plan IDs resolve to canonical snapshot associations", %{project: project} do
    %{plan: plan} = create_plan(project)
    assert {:ok, test} = report(project, plan, 0, shard_plan_id: String.upcase(plan.id))
    assert test.shard_plan_id == plan.id
    assert {:ok, loaded} = Tests.get_test(test.id, preload: [:shard_plan])
    assert loaded.shard_plan.id == plan.id
  end

  test "lost projection jobs are repaired and stale acknowledgements cannot clear newer work", %{project: project} do
    %{plan: plan} = create_plan(project)
    assert {:ok, _} = report(project, plan, 0)
    previous = Workflows.get(plan.id)
    jobs = from(j in Oban.Job, where: fragment("?->>'workflow_id' = ?", j.args, ^plan.id))
    Repo.delete_all(jobs)
    assert :ok = Workflows.reconcile_pending()
    assert_enqueued(worker: ProjectWorkflowWorker, args: %{workflow_id: plan.id})

    assert {:ok, _} = report(project, plan, 1)
    assert :ok = Workflows.mark_projected(previous)
    latest = Workflows.get(plan.id)
    assert latest.projected_version == previous.version
    assert latest.projected_version < latest.version

    assert :ok = perform_job(ProjectWorkflowWorker, %{workflow_id: plan.id, project_id: project.id})
    assert Workflows.get(plan.id).projected_version == latest.version
    assert :ok = Workflows.mark_projected(previous)
    assert Workflows.get(plan.id).projected_version == latest.version
    Repo.delete_all(jobs)
    assert :ok = Workflows.reconcile_pending()
    assert [] = all_enqueued(worker: ProjectWorkflowWorker, args: %{workflow_id: plan.id})
  end

  test "repair attempts rotate without resetting report-idle deadlines", %{project: project} do
    %{plan: first} = create_plan(project, %{reference: "repair-first"})
    %{plan: second} = create_plan(project, %{reference: "repair-second"})
    initial = Map.new([first, second], fn plan -> {plan.id, Workflows.get(plan.id).updated_at} end)
    jobs = from(j in Oban.Job, where: j.worker == "Tuist.Shards.Workers.ProjectWorkflowWorker")
    Repo.delete_all(jobs)

    assert :ok = Workflows.reconcile_pending(1)
    [first_job] = all_enqueued(worker: ProjectWorkflowWorker)
    Repo.delete_all(jobs)
    assert :ok = Workflows.reconcile_pending(1)
    [second_job] = all_enqueued(worker: ProjectWorkflowWorker)
    assert first_job.args["workflow_id"] != second_job.args["workflow_id"]

    Enum.each([first, second], fn plan ->
      workflow = Workflows.get(plan.id)
      assert workflow.projection_repair_at
      assert workflow.updated_at == initial[plan.id]
      assert workflow.projected_version == -1
    end)
  end

  test "failed publication leaves the durable projection cursor pending", %{project: project} do
    %{plan: plan} = create_plan(project)
    assert {:ok, _} = report(project, plan, 0)
    expect(IngestRepo, :insert_all, fn Test, _ -> raise "ClickHouse unavailable" end)

    assert_raise RuntimeError, "ClickHouse unavailable", fn ->
      ProjectWorkflowWorker.perform(%Oban.Job{args: %{"workflow_id" => plan.id, "project_id" => project.id}})
    end

    assert Workflows.get(plan.id).projected_version == -1
  end

  test "projection retry reads latest state and uses stable replacement versions", %{project: project} do
    %{plan: plan} = create_plan(project)
    assert {:ok, _} = report(project, plan, 0)
    assert {:ok, test} = report(project, plan, 1)

    parent = self()

    stub(IngestRepo, :insert_all, fn schema, rows, _opts ->
      send(parent, {:projected, schema, rows})
      {length(rows), nil}
    end)

    stub(IngestRepo, :insert_all, fn schema, rows ->
      send(parent, {:projected, schema, rows})
      {length(rows), nil}
    end)

    args = %{workflow_id: plan.id, project_id: project.id}
    assert :ok = perform_job(ProjectWorkflowWorker, args)
    assert_receive {:projected, Test, [%{id: id, status: "success", inserted_at: version}]}
    assert id == test.id
    assert version == test.inserted_at
    assert :ok = perform_job(ProjectWorkflowWorker, args)
    assert_receive {:projected, Test, [%{status: "success", inserted_at: ^version}]}
  end

  test "an executing projection cannot absorb a new committed report", %{project: project} do
    %{plan: plan} = create_plan(project)
    [job] = all_enqueued(worker: ProjectWorkflowWorker, args: %{workflow_id: plan.id})
    job |> Changeset.change(state: "executing") |> Repo.update!()
    assert {:ok, _} = report(project, plan, 0)
    assert [_new_job] = all_enqueued(worker: ProjectWorkflowWorker, args: %{workflow_id: plan.id})
  end

  test "the stale ClickHouse reaper cannot fail a completed workflow", %{project: project} do
    %{plan: plan} = create_plan(project)
    assert {:ok, _} = report(project, plan, 0)
    assert {:ok, final} = report(project, plan, 1)
    stale = %{final | status: "in_progress", inserted_at: ~N[2020-01-01 00:00:00.000000]}

    stub(ClickHouseRepo, :all, fn _ -> [] end)

    # The candidate query and latest-version query run in that order. Avoid
    # depending on the ClickHouse projection's actual visibility in this test.
    expect(ClickHouseRepo, :all, fn _ -> [stale.id] end)
    expect(ClickHouseRepo, :all, fn _, _opts -> [stale] end)
    assert :ok = Tests.expire_stale_in_progress_test_runs()
    assert Workflows.get_test(final.id).status == "success"
  end

  test "genuinely abandoned reports expire through the authoritative transaction", %{project: project} do
    %{plan: plan} = create_plan(project)
    assert {:ok, _} = report(project, plan, 0)
    workflow = Workflows.get(plan.id)
    old = DateTime.add(DateTime.utc_now(), -7, :hour)
    Repo.update_all(from(w in Workflow, where: w.id == ^plan.id), set: [updated_at: old])

    Workflows.expire_stale(DateTime.add(DateTime.utc_now(), -6, :hour))
    expired = Workflows.get(plan.id)
    assert expired.snapshot["status"] == "failure"
    assert expired.version > workflow.version
    assert expired.shards |> Enum.map(& &1.status) |> Enum.sort() == ["failure", "success"]
    assert_enqueued(worker: ProjectWorkflowWorker, args: %{workflow_id: plan.id})
  end

  test "project deletion cascades the authoritative plan and assignments", %{project: project} do
    %{plan: plan} = create_plan(project)
    Repo.delete!(project)
    refute Workflows.get(plan.id)
    refute Repo.exists?(from(s in WorkflowShard, where: s.workflow_id == ^plan.id))
    assert :ok = perform_job(ProjectWorkflowWorker, %{workflow_id: plan.id, project_id: project.id})
  end

  defp create_plan(project, overrides \\ %{}) do
    params = Map.merge(%{reference: "workflow", modules: ["AppTests", "CoreTests"], shard_total: 2}, overrides)
    Shards.create_shard_plan(project, params)
  end

  defp report(project, plan, index, overrides \\ []) do
    attrs = %{
      id: UUIDv7.generate(),
      project_id: project.id,
      account_id: project.account_id,
      shard_plan_id: plan.id,
      shard_index: index,
      status: "success",
      duration: 100,
      is_ci: false,
      build_system: "xcode",
      ran_at: NaiveDateTime.utc_now(),
      test_modules: []
    }

    Tests.create_test(Map.merge(attrs, Map.new(overrides)))
  end
end
