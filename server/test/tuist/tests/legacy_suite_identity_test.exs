defmodule Tuist.Tests.LegacySuiteIdentityTest do
  use TuistTestSupport.Cases.DataCase, async: true

  import Ecto.Query

  alias Tuist.Automations.Alerts.Event, as: AlertEvent
  alias Tuist.ClickHouseRepo
  alias Tuist.IngestRepo
  alias Tuist.Tests
  alias Tuist.Tests.Coverage.TestSources
  alias Tuist.Tests.CoverageTestSource
  alias Tuist.Tests.LegacySuiteIdentity
  alias Tuist.Tests.TestCaseEvent
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  describe "legacy_test_case_id/5" do
    test "is the ID the innermost suite gave a nested suite's test" do
      assert LegacySuiteIdentity.legacy_test_case_id(1, "xcode", "b()", "LibTests", "Outer/Inner") ==
               Tests.generate_test_case_id(1, "b()", "LibTests", "Inner")
    end

    test "is nil when the suite isn't nested" do
      assert LegacySuiteIdentity.legacy_test_case_id(1, "xcode", "b()", "LibTests", "Inner") == nil
      assert LegacySuiteIdentity.legacy_test_case_id(1, "xcode", "b()", "LibTests", "") == nil
    end

    test "is nil for other build systems, whose suites always kept their `/`" do
      assert LegacySuiteIdentity.legacy_test_case_id(1, "mix", "creates it", "OrdersTest", "create_order/2") == nil
    end
  end

  describe "carry_over/3" do
    test "reads the legacy IDs of a module with thousands of new nested tests in chunks" do
      # One query parameter holds about 3,000 UUIDs before ClickHouse rejects the request.
      test_cases =
        for i <- 1..5_000 do
          suite_name = "Outer/Inner#{i}"

          %{
            id: Tests.generate_test_case_id(1, "t()", "Big", suite_name),
            name: "t()",
            module_name: "Big",
            suite_name: suite_name
          }
        end

      assert LegacySuiteIdentity.carry_over(1, "xcode", test_cases) == MapSet.new()
    end
  end

  describe "ingesting a nested suite under its whole path" do
    setup do
      project = ProjectsFixtures.project_fixture()
      account = AccountsFixtures.user_fixture(preload: [:account]).account
      %{project: project, account: account}
    end

    test "carries the legacy ID's quarantine, flaky flag and automation status over", %{
      project: project,
      account: account
    } do
      {:ok, _} = create_test(project, account, "Inner", "main")
      legacy_id = Tests.generate_test_case_id(project.id, "b()", "LibTests", "Inner")
      {:ok, _} = Tests.update_test_case(legacy_id, %{state: "skipped", is_flaky: true})

      alert_id = UUIDv7.generate()
      triggered_at = NaiveDateTime.utc_now()

      IngestRepo.insert_all(AlertEvent, [
        %{
          id: UUIDv7.generate(),
          alert_id: alert_id,
          baseline_generation: 0,
          test_case_id: legacy_id,
          status: "triggered",
          triggered_at: triggered_at,
          inserted_at: triggered_at
        }
      ])

      {:ok, test} = create_test(project, account, "Outer/Inner", "feature")

      new_id = Tests.generate_test_case_id(project.id, "b()", "LibTests", "Outer/Inner")
      refute new_id == legacy_id

      {:ok, test_case} = Tests.get_test_case_by_id(new_id)
      assert test_case.suite_name == "Outer/Inner"
      assert test_case.state == "skipped"
      assert test_case.is_flaky == true

      assert [%{status: "triggered", alert_id: ^alert_id}] =
               ClickHouseRepo.all(from(e in AlertEvent, where: e.test_case_id == ^new_id))

      {[run], _} = Tests.list_test_case_runs(%{filters: [%{field: :test_run_id, op: :==, value: test.id}]})
      assert run.test_case_id == new_id
      assert run.is_new == false

      assert event_types(new_id) == event_types(legacy_id)
      assert Enum.count(event_types(new_id), &(&1 == "first_run")) == 1
    end

    test "carries the legacy ID's coverage versions over, so selection and carry keep its evidence", %{
      project: project,
      account: account
    } do
      {:ok, _} = create_test(project, account, "Inner", "main")
      legacy_id = Tests.generate_test_case_id(project.id, "b()", "LibTests", "Inner")
      run_id = UUIDv7.generate()
      ran_at = ~N[2026-11-01 10:00:00.000000]

      IngestRepo.insert_all(CoverageTestSource, [
        %{
          project_id: project.id,
          git_repository_id: 7,
          test_case_id: legacy_id,
          fingerprint: "abc",
          paths: ["Sources/Lib/B.swift"],
          unlined_paths: [],
          passed: true,
          test_run_id: run_id,
          git_commit_sha: "sha",
          ran_at: ran_at,
          inserted_at: ran_at
        }
      ])

      {:ok, _} = create_test(project, account, "Outer/Inner", "main")
      {:ok, _} = create_test(project, account, "Outer/Inner", "main")

      new_id = Tests.generate_test_case_id(project.id, "b()", "LibTests", "Outer/Inner")

      assert %{^new_id => [%{fingerprint: "abc", paths: ["Sources/Lib/B.swift"], passed: true, run_id: ^run_id}]} =
               TestSources.versions(project.id, 7, [new_id])

      assert [_] = TestSources.versions(project.id, 7, [legacy_id])[legacy_id]
    end

    test "leaves the legacy ID's state in place for clients that still report the innermost suite", %{
      project: project,
      account: account
    } do
      {:ok, _} = create_test(project, account, "Inner", "main")
      legacy_id = Tests.generate_test_case_id(project.id, "b()", "LibTests", "Inner")
      {:ok, _} = Tests.update_test_case(legacy_id, %{state: "muted"})

      {:ok, _} = create_test(project, account, "Outer/Inner", "main")

      {:ok, legacy} = Tests.get_test_case_by_id(legacy_id)
      assert legacy.state == "muted"
    end

    test "copies the ledger once, however many reports name the new suite path", %{
      project: project,
      account: account
    } do
      {:ok, _} = create_test(project, account, "Inner", "main")
      legacy_id = Tests.generate_test_case_id(project.id, "b()", "LibTests", "Inner")
      {:ok, _} = Tests.update_test_case(legacy_id, %{state: "muted"})

      {:ok, _} = create_test(project, account, "Outer/Inner", "main")
      {:ok, _} = create_test(project, account, "Outer/Inner", "main")

      new_id = Tests.generate_test_case_id(project.id, "b()", "LibTests", "Outer/Inner")
      assert Enum.count(event_types(new_id), &(&1 == "muted")) == 1
    end

    test "leaves a Mix describe holding a `/` alone", %{project: project, account: account} do
      {:ok, _} = create_test(project, account, "2", "main", build_system: "mix")
      legacy_id = Tests.generate_test_case_id(project.id, "b()", "LibTests", "2")
      {:ok, _} = Tests.update_test_case(legacy_id, %{state: "muted"})

      {:ok, _} = create_test(project, account, "create_order/2", "main", build_system: "mix")

      {:ok, test_case} =
        Tests.get_test_case_by_id(Tests.generate_test_case_id(project.id, "b()", "LibTests", "create_order/2"))

      assert test_case.state == "enabled"
    end

    test "records a first_run for a nested suite's test that never existed under its innermost suite", %{
      project: project,
      account: account
    } do
      {:ok, _} = create_test(project, account, "Outer/Inner", "main")

      new_id = Tests.generate_test_case_id(project.id, "b()", "LibTests", "Outer/Inner")
      assert event_types(new_id) == ["first_run"]
    end
  end

  defp create_test(project, account, suite_name, branch, opts \\ []) do
    Tests.create_test(%{
      build_system: Keyword.get(opts, :build_system, "xcode"),
      id: UUIDv7.generate(),
      project_id: project.id,
      account_id: account.id,
      duration: 1000,
      status: "success",
      model_identifier: "Mac15,6",
      macos_version: "14.0",
      xcode_version: "26.3",
      git_branch: branch,
      git_commit_sha: Ecto.UUID.generate(),
      ran_at: NaiveDateTime.utc_now(),
      is_ci: true,
      test_modules: [
        %{
          name: "LibTests",
          status: "success",
          duration: 1000,
          test_suites: [%{name: suite_name, status: "success", duration: 500}],
          test_cases: [%{name: "b()", test_suite_name: suite_name, status: "success", duration: 500}]
        }
      ]
    })
  end

  defp event_types(test_case_id) do
    from(e in TestCaseEvent, where: e.test_case_id == ^test_case_id, order_by: [e.inserted_at, e.event_type])
    |> ClickHouseRepo.all()
    |> Enum.uniq_by(& &1.id)
    |> Enum.map(& &1.event_type)
  end
end
