defmodule Tuist.Tests.EnumerationTest do
  use TuistTestSupport.Cases.DataCase, async: false
  use Mimic

  import Ecto.Query

  alias Ecto.Adapters.SQL.Sandbox
  alias Tuist.ClickHouseRepo
  alias Tuist.IngestRepo
  alias Tuist.Tests
  alias Tuist.Tests.Enumeration
  alias Tuist.Tests.TestCaseRun
  alias TuistTestSupport.Fixtures.CoverageFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures
  alias TuistTestSupport.Fixtures.ShardsFixtures

  setup do
    %{project: ProjectsFixtures.project_fixture()}
  end

  defp run(project, attrs) do
    {:ok, test} =
      RunsFixtures.test_fixture(
        Keyword.merge(
          [
            project_id: project.id,
            test_modules: [
              %{
                name: "AppTests",
                status: "success",
                duration: 10,
                test_cases: [
                  %{name: "testAdd()", test_suite_name: "MathTests", status: "success", duration: 5}
                ]
              }
            ]
          ],
          attrs
        )
      )

    test
  end

  test "stores every candidate by the test case's stable id, enabled or not", %{project: project} do
    test = run(project, [])

    Enumeration.record(test, [
      %{module: "AppTests", suite: "MathTests", name: "testAdd()", enabled: true},
      %{module: "AppTests", suite: "MathTests", name: "testSubtract()", enabled: true},
      %{"module" => "AppTests", "suite" => "", "name" => "freeFunction()"},
      %{module: "AppTests", suite: "MathTests", name: "testDisabled()", enabled: false}
    ])

    assert [
             %{suite_name: "", name: "freeFunction()", enabled: true},
             %{suite_name: "MathTests", name: "testAdd()", enabled: true},
             %{suite_name: "MathTests", name: "testDisabled()", enabled: false},
             %{suite_name: "MathTests", name: "testSubtract()", enabled: true, test_case_id: id}
           ] = CoverageFixtures.enumerated_tests(test)

    assert id == Tests.generate_test_case_id(project.id, "testSubtract()", "AppTests", "MathTests")
  end

  test "names a test skipped by a later run after the display name an earlier run recorded", %{project: project} do
    ran =
      run(project,
        test_modules: [
          %{
            name: "AppTests",
            status: "success",
            duration: 10,
            test_cases: [%{name: "Maps paths", test_suite_name: "MapperTests", status: "success", duration: 5}]
          }
        ]
      )

    Enumeration.record(ran, [
      %{module: "AppTests", suite: "MapperTests", name: "Maps paths", function: "map()", enabled: true}
    ])

    assert [%{name: "Maps paths", function_name: "map()"}] = CoverageFixtures.enumerated_tests(ran)

    skipped = run(project, [])

    Enumeration.record(skipped, [
      %{module: "AppTests", suite: "MathTests", name: "testAdd()", enabled: true},
      %{module: "AppTests", suite: "MapperTests", name: "map()", enabled: true}
    ])

    assert %{test_case_id: id} = Enum.find(CoverageFixtures.enumerated_tests(skipped), &(&1.name == "Maps paths"))
    assert id == Tests.generate_test_case_id(project.id, "Maps paths", "AppTests", "MapperTests")
  end

  test "reads back only the display names of the functions the run lacks one for", %{project: project} do
    ran = run(project, [])

    Enumeration.record(ran, [
      %{module: "AppTests", suite: "MapperTests", name: "Maps paths", function: "map()", enabled: true},
      %{module: "AppTests", suite: "MapperTests", name: "Parses input", function: "parse()", enabled: true}
    ])

    skipped = run(project, [])

    expect(ClickHouseRepo, :all, fn query ->
      rows = Mimic.call_original(ClickHouseRepo, :all, [query])
      send(self(), {:display_names, rows})
      rows
    end)

    Enumeration.record(skipped, [
      %{module: "AppTests", suite: "MapperTests", name: "map()", enabled: true},
      %{module: "AppTests", suite: "MathTests", name: "testAdd()", enabled: true}
    ])

    assert_received {:display_names, [{{"AppTests", "MapperTests", "map()"}, "Maps paths"}]}
  end

  test "looks up no display names when every test carries its function", %{project: project} do
    test = run(project, [])

    stub(ClickHouseRepo, :all, fn query ->
      send(self(), :queried)
      Mimic.call_original(ClickHouseRepo, :all, [query])
    end)

    Enumeration.record(test, [
      %{module: "AppTests", suite: "MapperTests", name: "Maps paths", function: "map()", enabled: true}
    ])

    refute_received :queried
    assert [%{name: "Maps paths"}] = CoverageFixtures.enumerated_tests(test)
  end

  test "stores nothing while the account's coverage flag is off", %{project: project} do
    test = run(project, [])
    stub(Tuist.FeatureFlags, :xcode_coverage_enabled?, fn _account -> false end)

    Enumeration.record(test, [%{module: "AppTests", suite: "MathTests", name: "testSubtract()"}])

    assert CoverageFixtures.enumerated_tests(test) == []
  end

  test "partitions the table by month, so its retention drops whole partitions" do
    # ClickHouse runs no DDL introspection inside the sandbox's transaction.
    %{rows: [[partition_key]]} =
      Sandbox.unboxed_run(IngestRepo, fn ->
        IngestRepo.query!(
          "SELECT partition_key FROM system.tables WHERE database = currentDatabase() AND name = 'test_run_enumerated_tests'"
        )
      end)

    assert partition_key == "toYYYYMM(inserted_at)"
  end

  describe "a failure storing them" do
    setup do
      stub(Enumeration, :record, fn _test, _enumerated_tests -> raise "ClickHouse timed out" end)
      :ok
    end

    test "leaves the run its test cases", %{project: project} do
      test = run(project, [])

      assert [_] = test_case_runs(test.id)
    end

    test "leaves a later shard its test cases", %{project: project} do
      plan = ShardsFixtures.shard_plan_fixture(project_id: project.id, shard_count: 2)
      first = run(project, shard_plan_id: plan.id, shard_index: 0)
      second = run(project, shard_plan_id: plan.id, shard_index: 1)

      assert second.id == first.id
      assert [_, _] = test_case_runs(first.id)
      assert {:ok, %{status: "success"}} = Tests.get_test(first.id)
    end
  end

  defp test_case_runs(test_run_id) do
    ClickHouseRepo.all(from(r in TestCaseRun, where: r.test_run_id == ^test_run_id, select: r.id))
  end
end
