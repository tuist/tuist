defmodule Tuist.Tests.FlakinessEnvironmentIngestionTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.ClickHouseRepo
  alias Tuist.IngestRepo
  alias Tuist.Repo
  alias Tuist.Tests
  alias Tuist.Tests.TestCaseRunFlakyCorrection
  alias Tuist.Tests.TestExecution
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures
  alias TuistTestSupport.Fixtures.ShardsFixtures

  @ios26 %{name: "iPhone 17", platform: "ios_simulator", os_version: "26.0"}
  @ios27 %{@ios26 | os_version: "27.0"}

  for {label, destinations} <- [
        {"OS version", [@ios27]},
        {"platform", [%{@ios26 | platform: "ios"}]},
        {"device", [%{@ios26 | name: "iPad"}]},
        {"missing destination", []},
        {"incomplete destination", [%{@ios26 | os_version: nil}]},
        {"multiple destinations", [@ios26, @ios27]}
      ],
      statuses <- [["success", "failure"], ["failure", "success"]] do
    @destinations destinations
    @statuses statuses
    test "isolates #{label} with #{hd(statuses)} arriving first" do
      project = ProjectsFixtures.project_fixture()
      [first_status, second_status] = @statuses
      first = ingest(project, first_status, [@ios26])
      second = ingest(project, second_status, @destinations)

      refute case_run(first).is_flaky
      refute case_run(second).is_flaky
      assert Repo.aggregate(TestCaseRunFlakyCorrection, :count) == 0
    end
  end

  test "a matching destination still flags the later failure, including duplicate and string-keyed destinations" do
    project = ProjectsFixtures.project_fixture()
    passing = ingest(project, "success", [@ios26])
    destination = Map.new(@ios26, fn {key, value} -> {Atom.to_string(key), value} end)
    failing = ingest(project, "failure", [destination, destination])

    refute case_run(passing).is_flaky
    assert case_run(failing).is_flaky
  end

  test "a later pass corrects only failures on its destination and preserves their execution reference" do
    project = ProjectsFixtures.project_fixture()
    ios26_failure = ingest(project, "failure", [@ios26])
    ios27_failure = ingest(project, "failure", [@ios27])
    ios27_run = case_run(ios27_failure)
    passing = ingest(project, "success", [@ios27])

    assert [%{test_case_run_id: id}] = Repo.all(TestCaseRunFlakyCorrection)
    assert id == ios27_run.id
    Tests.apply_test_case_run_flaky_corrections([id])

    refute case_run(ios26_failure).is_flaky
    refute case_run(passing).is_flaky
    assert case_run(ios27_failure).is_flaky
    assert Map.get(ios27_run, :test_execution_id)
    assert case_run(ios27_failure).test_execution_id == ios27_run.test_execution_id
  end

  test "case runs across modules share one execution and one copy of destination metadata" do
    project = ProjectsFixtures.project_fixture()

    run =
      ingest(project, "success", [@ios26, @ios26],
        test_modules: [
          %{
            name: "First",
            status: "success",
            duration: 100,
            test_cases: [%{name: "one", status: "success", duration: 50}, %{name: "two", status: "success", duration: 50}]
          },
          %{
            name: "Second",
            status: "success",
            duration: 100,
            test_cases: [%{name: "three", status: "success", duration: 100}]
          }
        ]
      )

    {cases, _} = Tests.list_test_case_runs(%{filters: [%{field: :test_run_id, op: :==, value: run.id}]})
    assert length(cases) == 3
    assert [execution_id] = Enum.uniq(Enum.map(cases, &Map.get(&1, :test_execution_id)))
    assert execution_id

    assert %{rows: [[1]]} =
             ClickHouseRepo.query!(
               "SELECT count() FROM test_executions FINAL WHERE project_id = {project_id:Int64}",
               %{project_id: project.id}
             )

    assert %{rows: [["ios_simulator", "26.0", "iPhone 17"]]} =
             ClickHouseRepo.query!(
               "SELECT platform, os_version, name FROM test_run_destinations WHERE test_execution_id = {id:UUID}",
               %{id: execution_id}
             )
  end

  for version <- [0, 1] do
    @version version
    test "version #{version} shards sharing a parent keep separate execution destinations" do
      project = ProjectsFixtures.project_fixture()
      plan = ShardsFixtures.shard_plan_fixture(project_id: project.id, shard_count: 2, reporting_version: @version)
      ingest(project, "success", [@ios26], shard_plan_id: plan.id, shard_index: 0)
      merged = ingest(project, "failure", [@ios27], shard_plan_id: plan.id, shard_index: 1)
      {cases, _} = Tests.list_test_case_runs(%{filters: [%{field: :test_run_id, op: :==, value: merged.id}]})
      assert length(cases) == 2
      refute Enum.any?(cases, & &1.is_flaky)
      assert length(Enum.uniq(Enum.map(cases, &Map.get(&1, :test_execution_id)))) == 2

      ingest(project, "success", [@ios27])
      failed = Enum.find(cases, &(&1.status == "failure"))
      assert [%{test_case_run_id: id}] = Repo.all(TestCaseRunFlakyCorrection)
      assert id == failed.id
    end
  end

  test "matching multi-destination reports do not establish cross-run flakiness" do
    project = ProjectsFixtures.project_fixture()
    ingest(project, "success", [@ios26, @ios27])
    failing = ingest(project, "failure", [@ios27, @ios26])

    refute case_run(failing).is_flaky
  end

  test "reports without destinations retain legacy cross-run detection" do
    project = ProjectsFixtures.project_fixture()
    ingest(project, "success", [])
    failing = ingest(project, "failure", [])

    assert case_run(failing).is_flaky
  end

  for {label, destinations} <- [{"missing", []}, {"known", [@ios26]}] do
    @destinations destinations
    test "historical case runs without execution references with #{label} destinations" do
      project = ProjectsFixtures.project_fixture()
      historical_pass(project, nil)
      failing = ingest(project, "failure", @destinations)

      assert case_run(failing).is_flaky == (@destinations == [])
    end

    test "an unavailable execution is not treated as missing metadata with #{label} destinations" do
      project = ProjectsFixtures.project_fixture()
      historical_pass(project, Ecto.UUID.generate())
      failing = ingest(project, "failure", @destinations)

      refute case_run(failing).is_flaky
    end
  end

  test "execution metadata must be written before case-run evidence" do
    project = ProjectsFixtures.project_fixture()

    stub(IngestRepo, :insert_all, fn
      TestExecution, _rows -> raise "execution write failed"
      schema, rows -> Mimic.call_original(IngestRepo, :insert_all, [schema, rows])
    end)

    assert_raise RuntimeError, "execution write failed", fn ->
      ingest(project, "success", [@ios26])
    end

    assert %{rows: [[0]]} =
             ClickHouseRepo.query!(
               "SELECT count() FROM test_case_runs WHERE project_id = {project_id:Int64}",
               %{project_id: project.id}
             )
  end

  test "immutable report replays reuse the execution reference and preserve destination attribution" do
    project = ProjectsFixtures.project_fixture()
    plan = ShardsFixtures.shard_plan_fixture(project_id: project.id, shard_count: 1, reporting_version: 1)
    options = [shard_plan_id: plan.id, shard_index: 0]
    first = ingest(project, "success", [@ios26], options)
    execution_id = case_run(first).test_execution_id
    replay = ingest(project, "success", [@ios26], options)

    assert case_run(replay).test_execution_id == execution_id

    assert %{rows: [[1]]} =
             ClickHouseRepo.query!(
               "SELECT count() FROM test_executions FINAL WHERE project_id = {project_id:Int64}",
               %{project_id: project.id}
             )

    {:ok, loaded} = Tests.get_test(replay.id, preload: [:run_destinations])
    assert [%{platform: "ios_simulator", os_version: "26.0", test_execution_id: ^execution_id}] = loaded.run_destinations
  end

  test "incomplete destinations cannot supply evidence to another incomplete report" do
    project = ProjectsFixtures.project_fixture()
    ingest(project, "success", [%{@ios26 | os_version: ""}])
    failing = ingest(project, "failure", [%{@ios26 | os_version: ""}])

    refute case_run(failing).is_flaky
  end

  test "multi-destination reports retain retry-based flaky evidence" do
    project = ProjectsFixtures.project_fixture()

    failing =
      ingest(project, "failure", [@ios26, @ios27],
        test_modules: [
          %{
            name: "AppTests",
            status: "failure",
            duration: 100,
            test_cases: [
              %{
                name: "testExample",
                status: "failure",
                duration: 100,
                repetitions: [
                  %{status: "failure", duration: 50},
                  %{status: "success", duration: 50}
                ]
              }
            ]
          }
        ]
      )

    assert case_run(failing).is_flaky
  end

  for version <- [0, 1] do
    @version version
    test "version #{version} shards use their own destination after a placeholder report" do
      project = ProjectsFixtures.project_fixture()
      ingest(project, "success", [@ios26])
      plan = ShardsFixtures.shard_plan_fixture(project_id: project.id, shard_count: 2, reporting_version: @version)
      shard = [shard_plan_id: plan.id, shard_index: 1]
      ingest(project, "processing", [], Keyword.put(shard, :test_modules, []))
      failing = ingest(project, "failure", [@ios27], shard)

      refute case_run(failing).is_flaky
      ingest(project, "success", [@ios27])
      assert [%{test_case_run_id: id}] = Repo.all(TestCaseRunFlakyCorrection)
      assert id == case_run(failing).id
    end
  end

  defp ingest(project, status, destinations, extra \\ []) do
    {:ok, test} =
      RunsFixtures.test_fixture(
        Keyword.merge(
          [
            project_id: project.id,
            account_id: project.account_id,
            git_commit_sha: "same-commit",
            scheme: "App",
            is_ci: true,
            status: status,
            run_destinations: destinations,
            test_modules: [
              %{
                name: "AppTests",
                status: status,
                duration: 100,
                test_cases: [%{name: "testExample", status: status, duration: 100}]
              }
            ]
          ],
          extra
        )
      )

    test
  end

  defp historical_pass(project, execution_id) do
    RunsFixtures.test_case_run_fixture(
      project_id: project.id,
      test_case_id: Tests.generate_test_case_id(project.id, "testExample", "AppTests", ""),
      test_execution_id: execution_id,
      git_commit_sha: "same-commit",
      scheme: "App",
      is_ci: true,
      status: "success"
    )
  end

  defp case_run(test) do
    {[run], _} = Tests.list_test_case_runs(%{filters: [%{field: :test_run_id, op: :==, value: test.id}]})
    run
  end
end
