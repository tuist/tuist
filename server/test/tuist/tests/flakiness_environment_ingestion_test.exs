defmodule Tuist.Tests.FlakinessEnvironmentIngestionTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.Repo
  alias Tuist.Tests
  alias Tuist.Tests.TestCaseRunFlakyCorrection
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

  test "a later pass corrects only failures on its destination and preserves their environment" do
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
    assert case_run(ios27_failure).flakiness_environment == ios27_run.flakiness_environment
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

  defp case_run(test) do
    {[run], _} = Tests.list_test_case_runs(%{filters: [%{field: :test_run_id, op: :==, value: test.id}]})
    run
  end
end
