defmodule Tuist.Tests.IngestionTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  import Ecto.Query
  import ExUnit.CaptureLog

  alias Tuist.Automations
  alias Tuist.ClickHouseRepo
  alias Tuist.IngestRepo
  alias Tuist.PubSub
  alias Tuist.Tasks
  alias Tuist.Tests
  alias Tuist.Tests.Test
  alias Tuist.Tests.TestCase
  alias Tuist.Tests.TestCaseFailure
  alias Tuist.Tests.TestCaseRun
  alias Tuist.Tests.TestCaseRunAttachment
  alias Tuist.Tests.TestCaseRunRepetition
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.ShardsFixtures

  setup do
    project = ProjectsFixtures.project_fixture()
    account = AccountsFixtures.user_fixture(preload: [:account]).account
    PubSub.subscribe("#{project.account.name}/#{project.name}")

    %{project: project, attrs: attributes(project.id, account.id)}
  end

  test "stages all core rows before one optional callback is admitted", %{attrs: attrs} do
    owner = self()

    stub(Tasks, :run_async, fn fun ->
      send(owner, {:followups, fun})
      {:ok, self()}
    end)

    assert {:ok, test} = Tests.create_test(attrs)
    assert_receive {:followups, fun}, 5_000
    refute_receive {:followups, _}
    assert is_function(fun, 0)

    [run] = ClickHouseRepo.all(from(r in TestCaseRun, where: r.test_run_id == ^test.id))
    assert ClickHouseRepo.exists?(from(c in TestCase, where: c.id == ^run.test_case_id))
    assert ClickHouseRepo.exists?(from(f in TestCaseFailure, where: f.test_case_run_id == ^run.id))
    assert ClickHouseRepo.aggregate(from(r in TestCaseRunRepetition, where: r.test_case_run_id == ^run.id), :count) == 2
    assert ClickHouseRepo.exists?(from(a in TestCaseRunAttachment, where: a.test_case_run_id == ^run.id))
  end

  for schema <- [TestCase, TestCaseFailure, TestCaseRunRepetition, TestCaseRunAttachment] do
    @schema schema
    test "#{inspect(schema)} staging errors still fail ingestion", %{attrs: attrs} do
      schema = @schema
      owner = self()

      stub(Tasks, :run_async, fn _fun ->
        send(owner, :followups_admitted)
        {:ok, self()}
      end)

      stub(IngestRepo, :insert_all, fn actual_schema, rows ->
        if actual_schema == schema do
          raise DBConnection.ConnectionError, message: "core staging unavailable"
        else
          Mimic.call_original(IngestRepo, :insert_all, [actual_schema, rows])
        end
      end)

      assert_raise DBConnection.ConnectionError, "core staging unavailable", fn -> Tests.create_test(attrs) end
      refute_receive :followups_admitted
    end
  end

  test "alert failures are reported without failing ingestion or blocking notification", %{attrs: attrs} do
    owner = self()
    stub(Tasks, :run_async, &Task.start/1)

    stub(Automations, :enqueue_flaky_alert_evaluations, fn _project_id, _ids ->
      raise DBConnection.ConnectionError, message: "alert scheduling unavailable"
    end)

    expect(Sentry, :capture_exception, fn error, opts ->
      send(owner, {:reported, error, opts})
      :ok
    end)

    capture_log(fn ->
      assert {:ok, test} = Tests.create_test(attrs)
      assert_receive {:reported, error, opts}, 5_000
      assert %DBConnection.ConnectionError{message: "alert scheduling unavailable"} = error
      assert opts[:extra] == %{test_run_id: test.id, data: "flaky alert evaluations"}
      assert [{_, _, _, _} | _] = opts[:stacktrace]
      assert_receive {:test_created, %{id: id}}, 5_000
      assert id == test.id
      assert length(test.test_case_runs) == 1
    end)
  end

  test "a flaky flag failure on a later shard does not block alerts or notification", %{attrs: attrs, project: project} do
    plan = ShardsFixtures.shard_plan_fixture(project_id: project.id, shard_count: 2)
    first_attrs = Map.merge(attrs, %{shard_plan_id: plan.id, shard_index: 0, is_ci: true, test_modules: []})
    assert {:ok, first} = Tests.create_test(first_attrs)
    assert_receive {:test_created, _}, 5_000
    owner = self()
    stub(Tasks, :run_async, &Task.start/1)

    stub(IngestRepo, :insert_all, fn schema, rows ->
      if schema == Test and Enum.any?(rows, &Map.get(&1, :is_flaky)) do
        raise DBConnection.ConnectionError, message: "flaky flag unavailable"
      else
        Mimic.call_original(IngestRepo, :insert_all, [schema, rows])
      end
    end)

    expect(Automations, :enqueue_flaky_alert_evaluations, fn project_id, ids ->
      send(owner, {:alerts, project_id, ids})
      :ok
    end)

    expect(Sentry, :capture_exception, fn error, opts ->
      send(owner, {:reported, error, opts})
      :ok
    end)

    capture_log(fn ->
      second_attrs = Map.merge(attrs, %{id: UUIDv7.generate(), shard_plan_id: plan.id, shard_index: 1, is_ci: true})
      assert {:ok, second} = Tests.create_test(second_attrs)
      assert second.id == first.id
      assert_receive {:reported, error, opts}, 5_000
      assert %DBConnection.ConnectionError{message: "flaky flag unavailable"} = error
      assert opts[:extra] == %{test_run_id: first.id, data: "flaky run flag"}
      assert [{_, _, _, _} | _] = opts[:stacktrace]
      assert_receive {:alerts, project_id, [_case_id]}, 5_000
      assert project_id == project.id
      assert_receive {:test_created, %{id: id}}, 5_000
      assert id == first.id
    end)
  end

  test "a blocked alert follow-up does not hold the ingestion response", %{attrs: attrs} do
    owner = self()
    stub(Tasks, :run_async, &Task.start/1)

    expect(Automations, :enqueue_flaky_alert_evaluations, fn _project_id, _ids ->
      send(owner, {:alert_started, self()})

      receive do
        :finish -> :ok
      after
        5_000 -> raise "alert follow-up was not released"
      end
    end)

    request = Task.async(fn -> Tests.create_test(attrs) end)
    assert_receive {:alert_started, followup}, 5_000

    try do
      assert followup != request.pid
      assert {:ok, _test} = Task.await(request, 5_000)
    after
      send(followup, :finish)
    end

    assert_receive {:test_created, _}, 5_000
  end

  test "alerts run once for the whole ingest rather than once per module", %{attrs: attrs, project: project} do
    owner = self()
    [first_module] = attrs.test_modules
    second_module = %{first_module | name: "second"}
    attrs = %{attrs | test_modules: [first_module, second_module]}

    expect(Automations, :enqueue_flaky_alert_evaluations, fn project_id, ids ->
      send(owner, {:alerts, project_id, ids})
      :ok
    end)

    assert {:ok, _} = Tests.create_test(attrs)
    assert_receive {:alerts, project_id, ids}, 5_000
    assert project_id == project.id
    assert length(Enum.uniq(ids)) == 2
    refute_receive {:alerts, _, _}
  end

  defp attributes(project_id, account_id) do
    %{
      id: UUIDv7.generate(),
      project_id: project_id,
      account_id: account_id,
      duration: 10,
      status: "success",
      ran_at: NaiveDateTime.utc_now(),
      is_ci: false,
      test_modules: [
        %{
          name: "module",
          status: "success",
          duration: 10,
          test_cases: [
            %{
              name: "case",
              status: "success",
              duration: 10,
              failures: [%{message: "first attempt", path: "Test.swift", line_number: 1}],
              repetitions: [
                %{repetition_number: 1, name: "first", status: "failure", duration: 5},
                %{repetition_number: 2, name: "retry", status: "success", duration: 5}
              ],
              attachments: [%{attachment_id: UUIDv7.generate(), file_name: "screenshot.png", repetition_number: nil}]
            }
          ]
        }
      ]
    }
  end
end
