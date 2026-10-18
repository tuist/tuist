defmodule Tuist.Shards.WorkflowConcurrencyTest do
  use ExUnit.Case, async: false
  use Mimic

  import Ecto.Query

  alias Ecto.Adapters.SQL.Sandbox
  alias Tuist.FeatureFlags
  alias Tuist.IngestRepo
  alias Tuist.Repo
  alias Tuist.Shards
  alias Tuist.Shards.Workflows
  alias Tuist.Tests
  alias Tuist.Tests.Test
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  setup :set_mimic_global

  setup do
    :ok = Sandbox.checkout(Repo, sandbox: false)
    :ok = Sandbox.checkout(IngestRepo, sandbox: false)
    stub(Tuist.Tasks, :run_async, fn fun -> fun.() end)
    stub(FeatureFlags, :postgres_shard_plans_enabled?, fn _ -> true end)
    user = AccountsFixtures.user_fixture(preload: [:account])
    project = ProjectsFixtures.project_fixture(account: user.account)

    %{plan: plan} =
      Shards.create_shard_plan(project, %{reference: "concurrent", modules: ["AppTests", "CoreTests"], shard_total: 2})

    on_exit(fn ->
      :ok = Sandbox.checkout(Repo, sandbox: false)

      try do
        Repo.delete_all(from(j in Oban.Job, where: fragment("?->>'workflow_id' = ?", j.args, ^plan.id)))
        Repo.delete!(project)
        Repo.delete!(user.account)
        Repo.delete!(user)
      after
        Sandbox.checkin(Repo)
      end
    end)

    %{project: project, plan: plan}
  end

  test "simultaneous first and final reports use one identity and complete without a ClickHouse merge base", %{
    project: project,
    plan: plan
  } do
    parent = self()

    tasks =
      Enum.map(0..1, fn index ->
        database_task(fn ->
          send(parent, {:ready, self()})

          receive do
            :report -> :ok
          after
            5000 -> flunk("report barrier was not released")
          end

          Tests.create_test(%{
            id: UUIDv7.generate(),
            project_id: project.id,
            account_id: project.account_id,
            shard_plan_id: plan.id,
            shard_index: index,
            status: "success",
            duration: (index + 1) * 100,
            scheme: if(index == 0, do: "App", else: ""),
            is_ci: false,
            build_system: "xcode",
            ran_at: NaiveDateTime.utc_now(),
            test_modules: []
          })
        end)
      end)

    try do
      assert_receive {:ready, _}, 5000
      assert_receive {:ready, _}, 5000
      Enum.each(tasks, &send(&1.pid, :report))
      results = Enum.map(tasks, &Task.await(&1, 10_000))
      assert Enum.all?(results, &match?({:ok, %Test{}}, &1))
      assert Enum.uniq(Enum.map(results, fn {:ok, test} -> test.id end)) == [plan.merged_test_run_id]
      assert Enum.any?(results, fn {:ok, test} -> test.status == "success" end)

      final = Workflows.get_test(plan.merged_test_run_id)
      assert final.status == "success"
      assert final.scheme == "App"
      assert final.duration == 200
      assert Enum.map(Workflows.get(plan.id).shards, & &1.status) == ["success", "success"]
    after
      Enum.each(tasks, &Task.shutdown(&1, 5000))
    end
  end

  test "the second database session merges only after the first transaction commits", %{project: project, plan: plan} do
    parent = self()

    first =
      database_task(fn ->
        Workflows.record_report(plan, 0, "success", 100, fn nil, ["success"] ->
          send(parent, :first_locked)

          receive do
            :commit -> :ok
          after
            5000 -> flunk("locked report was not released")
          end

          %Test{
            id: plan.merged_test_run_id,
            project_id: project.id,
            account_id: project.account_id,
            shard_plan_id: plan.id,
            status: "in_progress",
            duration: 100,
            ran_at: NaiveDateTime.utc_now()
          }
        end)
      end)

    try do
      assert_receive :first_locked, 5000

      second =
        database_task(fn ->
          send(parent, :second_started)

          Workflows.record_report(plan, 1, "success", 200, fn previous, statuses ->
            send(parent, :second_locked)
            assert previous.status == "in_progress"
            assert statuses == ["success", "success"]
            %{previous | status: "success", duration: 200}
          end)
        end)

      try do
        assert_receive :second_started, 5000
        refute_receive :second_locked, 100
        send(first.pid, :commit)
        assert {:ok, first_snapshot} = Task.await(first, 5000)
        assert {:ok, final_snapshot} = Task.await(second, 5000)
        assert final_snapshot.id == first_snapshot.id
        assert NaiveDateTime.after?(final_snapshot.inserted_at, first_snapshot.inserted_at)
        assert Workflows.get_test(plan.merged_test_run_id).status == "success"
      after
        Task.shutdown(second, 5000)
      end
    after
      send(first.pid, :commit)
      Task.shutdown(first, 5000)
    end
  end

  defp database_task(fun) do
    Task.async(fn ->
      :ok = Sandbox.checkout(Repo, sandbox: false)
      :ok = Sandbox.checkout(IngestRepo, sandbox: false)

      try do
        fun.()
      after
        Sandbox.checkin(IngestRepo)
        Sandbox.checkin(Repo)
      end
    end)
  end
end
