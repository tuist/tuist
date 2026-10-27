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

  test "unsigned follow-ups notify dashboards without scheduling flaky alerts", %{attrs: attrs} do
    owner = self()

    stub(Tasks, :run_async, fn fun ->
      send(owner, {:followups, fun})
      {:ok, self()}
    end)

    stub(Automations, :enqueue_flaky_alert_evaluations, fn project_id, ids ->
      send(owner, {:alerts, project_id, ids})
      :ok
    end)

    assert {:ok, signed} = Tests.create_test(attrs)
    assert_receive {:followups, _signed_followups}, 5_000

    unsigned_attrs =
      Map.merge(attrs, %{
        id: UUIDv7.generate(),
        is_ci: true,
        account_id: 0,
        actor_account_id: 0,
        submission_auth: "network_trusted"
      })

    assert {:ok, unsigned} = Tests.create_test(unsigned_attrs)
    assert hd(unsigned.test_case_runs).test_case_id == hd(signed.test_case_runs).test_case_id
    assert hd(unsigned.test_case_runs).test_case_id
    assert_receive {:followups, followups}, 5_000
    followups.()

    assert_receive {:test_created, %{id: id}}, 5_000
    assert id == unsigned.id
    refute_receive {:alerts, _, _}
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

  test "a delayed first-shard callback cannot overwrite the completed merged run", %{attrs: attrs, project: project} do
    cases = [%{name: "case", status: "success", duration: 10}]
    modules = [%{name: "module", status: "success", duration: 10, test_cases: cases}]
    attrs = Map.merge(attrs, %{is_ci: true, git_commit_sha: "delayed-flag", test_modules: modules})
    assert {:ok, _passing} = Tests.create_test(attrs)
    assert_receive {:test_created, _}, 5_000
    owner = self()

    stub(Tasks, :run_async, fn fun ->
      send(owner, {:followups, fun})
      {:ok, self()}
    end)

    plan = ShardsFixtures.shard_plan_fixture(project_id: project.id, shard_count: 2)
    failing_modules = put_in(modules, [Access.at(0), :test_cases, Access.at(0), :status], "failure")

    first_attrs =
      Map.merge(attrs, %{id: UUIDv7.generate(), shard_plan_id: plan.id, shard_index: 0, test_modules: failing_modules})

    assert {:ok, first} = Tests.create_test(first_attrs)
    assert_receive {:followups, first_followups}, 5_000
    assert hd(first.test_case_runs).is_flaky

    second_attrs =
      Map.merge(attrs, %{
        id: UUIDv7.generate(),
        shard_plan_id: plan.id,
        shard_index: 1,
        duration: 100,
        xcode_version: "17.0",
        test_modules: []
      })

    assert {:ok, second} = Tests.create_test(second_attrs)
    assert_receive {:followups, second_followups}, 5_000
    assert second.status == "success"
    first_followups.()
    second_followups.()

    assert {:ok, latest} = Tests.get_test(first.id)
    assert latest.status == "success"
    assert latest.duration == 100
    assert latest.xcode_version == "17.0"
    assert latest.is_flaky == second.is_flaky
  end

  test "a flaky flag failure on a new run does not block alerts or notification", %{attrs: attrs, project: project} do
    attrs = cross_run_attrs(attrs)
    assert {:ok, _passing} = Tests.create_test(attrs)
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

    stub(Automations, :enqueue_flaky_alert_evaluations, fn project_id, ids ->
      send(owner, {:alerts, project_id, ids})
      :ok
    end)

    expect(Sentry, :capture_exception, fn error, opts ->
      send(owner, {:reported, error, opts})
      :ok
    end)

    capture_log(fn ->
      second_attrs = failing_run_attrs(attrs)
      assert {:ok, second} = Tests.create_test(second_attrs)
      assert_receive {:reported, error, opts}, 5_000
      assert %DBConnection.ConnectionError{message: "flaky flag unavailable"} = error
      assert opts[:extra] == %{test_run_id: second.id, data: "flaky run flag"}
      assert [{_, _, _, _} | _] = opts[:stacktrace]
      assert_receive {:alerts, project_id, [_case_id]}, 5_000
      assert project_id == project.id
      assert_receive {:test_created, %{id: id}}, 5_000
      assert id == second.id
      refute_receive {:alerts, _, _}
    end)
  end

  test "a flag amendment never outranks a core row one microsecond newer", %{attrs: attrs} do
    attrs = cross_run_attrs(attrs)
    assert {:ok, _passing} = Tests.create_test(attrs)
    assert_receive {:test_created, _}, 5_000
    owner = self()

    stub(Tasks, :run_async, fn fun ->
      send(owner, {:followups, fun})
      {:ok, self()}
    end)

    assert {:ok, failed} = Tests.create_test(failing_run_attrs(attrs))
    assert_receive {:followups, followups}, 5_000

    newer = %{
      failed
      | status: "success",
        duration: 100,
        inserted_at: NaiveDateTime.add(failed.inserted_at, 1, :microsecond)
    }

    IngestRepo.insert_all(Test, [Map.take(Map.from_struct(newer), Test.__schema__(:fields))])

    stub(IngestRepo, :insert_all, fn schema, rows ->
      if schema == Test, do: send(owner, {:flag_write, rows})
      Mimic.call_original(IngestRepo, :insert_all, [schema, rows])
    end)

    followups.()
    assert_receive {:flag_write, [amendment]}, 5_000
    assert amendment.inserted_at == failed.inserted_at

    assert {:ok, latest} = Tests.get_test(failed.id)
    assert latest.status == "success"
    assert latest.duration == 100
    assert latest.inserted_at == newer.inserted_at
  end

  test "inferred flakiness also flags a run of an already-known flaky case", %{attrs: attrs} do
    attrs = cross_run_attrs(attrs)
    assert {:ok, passing} = Tests.create_test(attrs)
    [run] = passing.test_case_runs
    assert {:ok, _} = Tests.update_test_case(run.test_case_id, %{is_flaky: true})
    assert {:ok, failed} = Tests.create_test(failing_run_attrs(attrs))
    assert hd(failed.test_case_runs).is_flaky
    assert ClickHouseRepo.one(from(t in Test, hints: ["FINAL"], where: t.id == ^failed.id, select: t.is_flaky))
  end

  test "a flaky local case run does not flag its parent", %{attrs: attrs} do
    assert {:ok, local} = Tests.create_test(attrs)
    assert hd(local.test_case_runs).is_flaky
    refute ClickHouseRepo.one(from(t in Test, hints: ["FINAL"], where: t.id == ^local.id, select: t.is_flaky))
  end

  for flush_mode <- [:one_block, :separate_blocks] do
    @flush_mode flush_mode
    test "unsharded flag amendments follow their buffered parent with #{flush_mode}", %{attrs: attrs} do
      attrs = cross_run_attrs(attrs)
      assert {:ok, _passing} = Tests.create_test(attrs)
      queue = start_supervised!({Agent, fn -> [] end})

      stub(Test.Buffer, :insert, fn row ->
        Agent.update(queue, &[row | &1])
        {:ok, row}
      end)

      assert {:ok, failed} = Tests.create_test(failing_run_attrs(attrs))
      queued = queue |> Agent.get(&Enum.reverse/1) |> Enum.map(&Map.take(Map.from_struct(&1), Test.__schema__(:fields)))
      assert Enum.map(queued, & &1.is_flaky) == [false, true]
      assert Enum.map(queued, & &1.inserted_at) == [failed.inserted_at, failed.inserted_at]

      if @flush_mode == :one_block do
        IngestRepo.insert_all(Test, queued)
      else
        Enum.each(queued, &IngestRepo.insert_all(Test, [&1]))
      end

      assert ClickHouseRepo.one(from(t in Test, hints: ["FINAL"], where: t.id == ^failed.id, select: t.is_flaky))
    end
  end

  test "a later shard preserves an equal-version flag amendment in its merge base", %{attrs: attrs, project: project} do
    plan = ShardsFixtures.shard_plan_fixture(project_id: project.id, shard_count: 2)
    attrs = Map.merge(attrs, %{is_ci: true, shard_plan_id: plan.id, shard_index: 0, test_modules: []})
    assert {:ok, first} = Tests.create_test(attrs)
    amendment = %{first | is_flaky: true}
    IngestRepo.insert_all(Test, [Map.take(Map.from_struct(amendment), Test.__schema__(:fields))])
    owner = self()

    stub(ClickHouseRepo, :one, fn query ->
      if query.from.source == {"test_runs", Test} do
        order =
          for %{expr: expr} <- query.order_bys,
              {direction, {{:., _, [_, field]}, _, []}} <- expr,
              do: {direction, field}

        send(owner, {:merge_order, order})
      end

      Mimic.call_original(ClickHouseRepo, :one, [query])
    end)

    assert {:ok, second} = Tests.create_test(%{attrs | id: UUIDv7.generate(), shard_index: 1})
    assert_receive {:merge_order, order}, 5_000
    assert order == [desc: :inserted_at, desc: :is_flaky]
    assert second.is_flaky
    assert ClickHouseRepo.one(from(t in Test, hints: ["FINAL"], where: t.id == ^second.id, select: t.is_flaky))
  end

  test "a later shard keeps raw duplicate-identity retry flakiness", %{attrs: attrs, project: project} do
    plan = ShardsFixtures.shard_plan_fixture(project_id: project.id, shard_count: 2)

    assert {:ok, _first} =
             Tests.create_test(Map.merge(attrs, %{is_ci: true, shard_plan_id: plan.id, shard_index: 0, test_modules: []}))

    [module] = attrs.test_modules
    [flaky_case] = module.test_cases
    clean_duplicate = %{flaky_case | repetitions: []}

    attrs =
      Map.merge(attrs, %{
        id: UUIDv7.generate(),
        is_ci: true,
        shard_plan_id: plan.id,
        shard_index: 1,
        test_modules: [%{module | test_cases: [flaky_case, clean_duplicate]}]
      })

    assert {:ok, second} = Tests.create_test(attrs)
    assert second.is_flaky
  end

  test "a later shard folds its flag into exactly one primary write", %{attrs: attrs, project: project} do
    plan = ShardsFixtures.shard_plan_fixture(project_id: project.id, shard_count: 2)
    first_attrs = Map.merge(attrs, %{shard_plan_id: plan.id, shard_index: 0, is_ci: true, test_modules: []})
    assert {:ok, first} = Tests.create_test(first_attrs)
    assert_receive {:test_created, _}, 5_000
    owner = self()

    stub(IngestRepo, :insert_all, fn schema, rows ->
      if schema == Test, do: send(owner, {:parent_write, rows})
      Mimic.call_original(IngestRepo, :insert_all, [schema, rows])
    end)

    second_attrs = Map.merge(attrs, %{id: UUIDv7.generate(), shard_plan_id: plan.id, shard_index: 1, is_ci: true})
    assert {:ok, second} = Tests.create_test(second_attrs)
    assert second.id == first.id
    assert second.is_flaky
    assert_receive {:parent_write, [row]}, 5_000
    assert row.is_flaky
    assert row.inserted_at == second.inserted_at
    refute_receive {:parent_write, _}
  end

  test "a flag-buffer exit does not prevent alerts or notification", %{attrs: attrs} do
    attrs = cross_run_attrs(attrs)
    assert {:ok, _passing} = Tests.create_test(attrs)
    assert_receive {:test_created, _}, 5_000
    owner = self()
    stub(Tasks, :run_async, &Task.start/1)

    stub(Test.Buffer, :insert, fn row ->
      if row.is_flaky do
        send(owner, :flag_buffer_exited)
        exit(:noproc)
      else
        Mimic.call_original(Test.Buffer, :insert, [row])
      end
    end)

    stub(Automations, :enqueue_flaky_alert_evaluations, fn project_id, ids ->
      send(owner, {:alerts, project_id, ids})
      :ok
    end)

    capture_log(fn ->
      assert {:ok, failed} = Tests.create_test(failing_run_attrs(attrs))
      assert_receive :flag_buffer_exited, 5_000
      assert_receive {:alerts, project_id, [_id]}, 5_000
      assert project_id == failed.project_id
      assert_receive {:test_created, %{id: id}}, 5_000
      assert id == failed.id
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

    stub(Automations, :enqueue_flaky_alert_evaluations, fn project_id, ids ->
      send(owner, {:alerts, project_id, ids})
      :ok
    end)

    assert {:ok, _} = Tests.create_test(attrs)
    assert_receive {:alerts, project_id, ids}, 5_000
    assert project_id == project.id
    assert length(Enum.uniq(ids)) == 2
    refute_receive {:alerts, _, _}
  end

  defp cross_run_attrs(attrs) do
    Map.merge(attrs, %{
      is_ci: true,
      git_commit_sha: "same-commit",
      test_modules: [
        %{name: "module", status: "success", duration: 10, test_cases: [%{name: "case", status: "success", duration: 10}]}
      ]
    })
  end

  defp failing_run_attrs(attrs) do
    attrs
    |> Map.merge(%{id: UUIDv7.generate(), status: "failure"})
    |> put_in([:test_modules, Access.at(0), :test_cases, Access.at(0), :status], "failure")
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
