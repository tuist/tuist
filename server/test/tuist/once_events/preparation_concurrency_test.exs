defmodule Tuist.OnceEvents.PreparationConcurrencyTest do
  use ExUnit.Case, async: false
  use Mimic

  import Ecto.Query

  alias Ecto.Adapters.SQL.Sandbox
  alias Tuist.Accounts.Account
  alias Tuist.Accounts.User
  alias Tuist.Ingestion.Capture
  alias Tuist.OnceEvents
  alias Tuist.OnceEvents.TestReportIngestor
  alias Tuist.OnceEvents.TestReportPublication
  alias Tuist.Projects.Project
  alias Tuist.Repo
  alias Tuist.Tests.TestCaseRunFlakyCorrection
  alias Tuist.Tests.Workers.CorrectTestCaseRunFlakyStateWorker
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  test "a superseded preparer rolls back its snapshot and PostgreSQL effects" do
    clickhouse_owner = Sandbox.start_owner!(Tuist.IngestRepo, shared: true)
    on_exit(fn -> Sandbox.stop_owner(clickhouse_owner) end)
    stub(Tuist.Tasks, :run_async, fn fun -> fun.() end)
    correction_id = Ecto.UUID.generate()
    batch_id = Ecto.UUID.generate()

    {project, run} =
      Sandbox.unboxed_run(Repo, fn ->
        user = AccountsFixtures.user_fixture()
        project = ProjectsFixtures.project_fixture(account: user.account)

        on_exit(fn ->
          Sandbox.unboxed_run(Repo, fn ->
            Repo.delete_all(from(c in TestCaseRunFlakyCorrection, where: c.test_case_run_id == ^correction_id))
            Repo.delete_all(from(j in Oban.Job, where: j.args["batch_id"] == ^batch_id))
            run_ids = Repo.all(from(r in OnceEvents.Run, where: r.project_id == ^project.id, select: r.id))
            Repo.delete_all(from(j in Oban.Job, where: j.args["run_id"] in ^run_ids))
            Repo.delete_all(from(p in Project, where: p.id == ^project.id))
            Repo.delete_all(from(a in Account, where: a.id == ^user.account.id))
            Repo.delete_all(from(u in User, where: u.id == ^user.id))
          end)
        end)

        {:ok, run} =
          OnceEvents.upsert_run(%{
            project_id: project.id,
            run_id: "preparation-fence",
            kind: "test",
            command_display: "once test //...",
            git_rev: "abc123",
            started_at: DateTime.utc_now()
          })

        :ok =
          OnceEvents.ingest_test_case_run(run, %{
            target_execution_id: "target",
            suite_id: "unit",
            case_id: "case",
            name: "case",
            attempt: 1,
            result: "passed",
            duration_ms: 10,
            started_at: DateTime.utc_now(),
            finished_at: DateTime.utc_now()
          })

        {:ok, run} =
          OnceEvents.finalize_run(run, %{
            finalization: "finalized",
            exit_status: 0,
            wall_ms: 10,
            finalized_at: DateTime.utc_now()
          })

        {:ok, _} = TestReportIngestor.enqueue(run)
        {project, run}
      end)

    parent = self()

    stub(Tuist.Tests, :create_test, fn attrs ->
      send(parent, {:builder_entered, self()})

      receive do
        {:build, effects?} ->
          if effects? do
            Repo.transaction(fn ->
              Repo.insert!(%TestCaseRunFlakyCorrection{
                test_case_run_id: correction_id,
                project_id: project.id,
                test_case_id: Ecto.UUID.generate(),
                git_commit_sha: "abc123"
              })

              %{batch_id: batch_id, test_case_run_ids: [correction_id]}
              |> CorrectTestCaseRunFlakyStateWorker.new()
              |> Oban.insert!()
            end)

            assert Repo.aggregate(
                     from(c in TestCaseRunFlakyCorrection, where: c.test_case_run_id == ^correction_id),
                     :count
                   ) == 1

            assert Repo.aggregate(from(j in Oban.Job, where: j.args["batch_id"] == ^batch_id), :count) == 1
          end
      after
        10_000 -> flunk("builder admission missing")
      end

      %{rows: [[connection]]} = Repo.query!("SELECT pg_backend_pid()")
      send(parent, {:builder_ready, self(), connection})

      receive do
        :finish -> Mimic.call_original(Tuist.Tests, :create_test, [attrs])
      after
        10_000 -> flunk("builder release missing")
      end
    end)

    first = start_preparer(run.id)
    assert_receive {:builder_entered, first_pid}, 5_000
    send(first_pid, {:build, true})
    assert_receive {:builder_ready, ^first_pid, first_connection}, 5_000

    original_owner =
      Sandbox.unboxed_run(Repo, fn ->
        publication = Repo.get!(TestReportPublication, run.id)
        assert publication.preparation_attempts == 1
        assert publication.owner

        Repo.update_all(from(p in TestReportPublication, where: p.id == ^run.id),
          set: [updated_at: DateTime.add(DateTime.utc_now(:second), -1_000)]
        )

        publication.owner
      end)

    second = start_preparer(run.id)
    assert_receive {:builder_entered, second_pid}, 5_000
    send(second_pid, {:build, false})
    assert_receive {:builder_ready, ^second_pid, second_connection}, 5_000
    refute first_connection == second_connection

    successor_owner =
      Sandbox.unboxed_run(Repo, fn ->
        publication = Repo.get!(TestReportPublication, run.id)
        assert publication.preparation_attempts == 2
        assert publication.owner != original_owner
        publication.owner
      end)

    send(first_pid, :finish)
    assert Task.await(first, 15_000) == {{:ok, :in_progress}, false}

    Sandbox.unboxed_run(Repo, fn ->
      publication = Repo.get!(TestReportPublication, run.id)
      assert publication.owner == successor_owner
      assert publication.state == "preparing"
      assert publication.payload == nil
      assert publication.preparation_attempts == 2

      assert Repo.aggregate(from(c in TestCaseRunFlakyCorrection, where: c.test_case_run_id == ^correction_id), :count) ==
               0

      assert Repo.aggregate(from(j in Oban.Job, where: j.args["batch_id"] == ^batch_id), :count) == 0
    end)

    send(second_pid, :finish)
    assert {{:ok, publication}, false} = Task.await(second, 15_000)
    assert publication.state == "pending"
    assert publication.owner == nil
    assert publication.preparation_attempts == 2
    assert publication.payload == nil

    Sandbox.unboxed_run(Repo, fn ->
      stored = Repo.get!(TestReportPublication, run.id)
      assert stored.state == "pending"
      assert stored.owner == nil
      assert stored.preparation_attempts == 2
      assert stored.payload
    end)
  end

  defp start_preparer(id) do
    parent = self()

    task =
      Task.async(fn ->
        receive do
          :start -> Sandbox.unboxed_run(Repo, fn -> {TestReportIngestor.prepare_snapshot(id), Capture.active?()} end)
        end
      end)

    on_exit(fn -> if Process.alive?(task.pid), do: Process.exit(task.pid, :kill) end)
    for module <- [Tuist.Tests, Tuist.Tasks], do: allow(module, parent, task.pid)
    send(task.pid, :start)
    task
  end
end
