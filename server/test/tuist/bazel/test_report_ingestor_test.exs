defmodule Tuist.Bazel.TestReportIngestorTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.Bazel.TestReportIngestor
  alias Tuist.Projects.Project

  setup do
    stub(Tuist.Tests, :get_test_case_states_at, fn _project_id, ids, _at ->
      Map.new(ids, &{&1, %{state: "enabled", is_flaky: false}})
    end)

    :ok
  end

  setup :verify_on_exit!

  test "creates one run with independently derived modules and invocation context" do
    project = %Project{id: 1, account_id: 1, build_system: :bazel}
    test_run_id = UUIDv7.generate()

    invocation = %{
      test_run_id: test_run_id,
      invocation_id: "invocation-1",
      duration_ms: 4_000,
      exit_code: 3,
      target_patterns: ["//...", "-//App:SkippedTests"],
      git_branch: "feature/bazel-tests",
      git_commit_sha: "abcdef123456",
      finished_at: ~N[2026-09-04 12:00:04],
      is_ci: true
    }

    passing_report = """
    <testsuite name="PassingSuite">
      <testcase name="passes" time="0.100" />
    </testsuite>
    """

    failing_report = """
    <testsuite name="FailingSuite">
      <testcase name="fails" time="0.200"><failure>Expected true</failure></testcase>
    </testsuite>
    """

    results = [
      result("//App:PassingTests", "success", 100, passing_report),
      result("//App:FailingTests", "failure", 200, failing_report)
    ]

    expect(Tuist.Tests, :create_test, fn attrs ->
      assert attrs.id == test_run_id
      assert attrs.status == "failure"
      assert attrs.duration == 4_000
      assert attrs.scheme == "//..."
      assert attrs.git_branch == "feature/bazel-tests"
      assert attrs.git_ref == "refs/heads/feature/bazel-tests"
      assert attrs.git_commit_sha == "abcdef123456"
      assert attrs.is_ci
      assert attrs.build_system == "bazel"
      assert attrs.bazel_invocation_id == "invocation-1"

      modules = Map.new(attrs.test_modules, &{&1.name, &1})
      assert modules["//App:PassingTests"].status == "success"
      assert modules["//App:PassingTests"].duration == 110
      assert modules["//App:FailingTests"].status == "failure"
      assert modules["//App:FailingTests"].duration == 220

      {:ok, %{id: test_run_id}}
    end)

    summaries = [
      %{target_label: "//App:PassingTests", status: "success", duration_ms: 110},
      %{target_label: "//App:FailingTests", status: "failure", duration_ms: 220}
    ]

    assert {:ok, %{id: ^test_run_id}} = TestReportIngestor.ingest(project, invocation, results, summaries)
  end

  test "preserves attempts as repetitions so flaky cases can be detected" do
    project = %Project{id: 1, account_id: 1, build_system: :bazel}
    test_run_id = UUIDv7.generate()

    invocation = %{
      test_run_id: test_run_id,
      invocation_id: "invocation-2",
      duration_ms: 1_000,
      exit_code: 0,
      target_patterns: [],
      git_branch: "main",
      git_commit_sha: "abcdef",
      finished_at: ~N[2026-09-04 12:00:01],
      is_ci: false
    }

    failed = ~s(<testsuite name="Suite"><testcase name="case"><failure>first attempt</failure></testcase></testsuite>)
    passed = ~s(<testsuite name="Suite"><testcase name="case" /></testsuite>)

    results = [
      result("//App:FlakyTests", "flaky", 200, passed, attempt: 2),
      result("//App:FlakyTests", "failure", 300, failed, attempt: 1)
    ]

    expect(Tuist.Tests, :create_test, fn attrs ->
      assert attrs.is_ci
      assert attrs.scheme == "//App:FlakyTests"
      assert [%{status: "success", test_cases: [test_case]}] = attrs.test_modules
      assert test_case.status == "success"
      assert Enum.map(test_case.repetitions, & &1.status) == ["failure", "success"]
      assert Enum.map(test_case.repetitions, & &1.repetition_number) == [1, 2]
      assert Enum.map(test_case.repetitions, & &1.name) == ["Attempt 1", "Attempt 2"]
      assert [%{message: "first attempt"}] = test_case.failures
      {:ok, %{id: test_run_id}}
    end)

    assert {:ok, %{id: ^test_run_id}} = TestReportIngestor.ingest(project, invocation, results, [])
  end

  test "preserves skipped targets, suites, cases, and runs" do
    project = %Project{id: 1, account_id: 1, build_system: :bazel}
    test_run_id = UUIDv7.generate()

    invocation = %{
      test_run_id: test_run_id,
      invocation_id: "invocation-skipped",
      duration_ms: 10,
      exit_code: 0,
      target_patterns: ["//App:SkippedTests"],
      git_branch: "main",
      git_commit_sha: "abcdef",
      finished_at: ~N[2026-09-04 12:00:01],
      is_ci: false
    }

    report = ~s(<testsuite name="SkippedSuite"><testcase name="skipped"><skipped /></testcase></testsuite>)
    results = [result("//App:SkippedTests", "skipped", 10, report)]
    summaries = [%{target_label: "//App:SkippedTests", status: "skipped", duration_ms: 10}]

    expect(Tuist.Tests, :create_test, fn attrs ->
      assert attrs.status == "skipped"

      assert [module] = attrs.test_modules
      assert module.status == "skipped"
      assert [%{status: "skipped"}] = module.test_suites
      assert [%{status: "skipped", repetitions: [%{status: "skipped"}]}] = module.test_cases
      {:ok, %{id: test_run_id}}
    end)

    assert {:ok, %{id: ^test_run_id}} = TestReportIngestor.ingest(project, invocation, results, summaries)
  end

  test "a later successful run does not hide a terminal failure in another run" do
    project = %Project{id: 1, account_id: 1, build_system: :bazel}
    failed = ~s(<testsuite name="Suite"><testcase name="case"><failure>failed run</failure></testcase></testsuite>)
    passed = ~s(<testsuite name="Suite"><testcase name="case" /></testsuite>)

    results = [
      result("//App:Tests", "success", 20, passed, run: 2),
      result("//App:Tests", "failure", 30, failed, run: 1)
    ]

    expect(Tuist.Tests, :create_test, fn attrs ->
      assert [%{status: "failure", test_cases: [%{status: "failure"} = test_case]}] = attrs.test_modules
      assert Enum.map(test_case.repetitions, & &1.status) == ["failure", "success"]
      {:ok, %{id: attrs.id}}
    end)

    assert {:ok, _} = TestReportIngestor.ingest(project, invocation(), results, [])
  end

  test "quarantine attribution uses the invocation start rather than processing time" do
    project = %Project{id: 1, account_id: 1, build_system: :bazel}
    invocation = invocation()
    started_at = invocation.started_at
    report = ~s(<testsuite name="Suite"><testcase name="case"><failure>failure</failure></testcase></testsuite>)

    expect(Tuist.Tests, :get_test_case_states_at, fn 1, [id], ^started_at ->
      %{id => %{state: "muted", is_flaky: false}}
    end)

    expect(Tuist.Tests, :create_test, fn attrs ->
      assert [%{test_cases: [%{status: "failure", is_quarantined: true}]}] = attrs.test_modules
      {:ok, %{id: attrs.id}}
    end)

    assert {:ok, _} =
             TestReportIngestor.ingest(project, invocation, [result("//App:Tests", "failure", 10, report)], [])
  end

  defp invocation do
    %{
      test_run_id: UUIDv7.generate(),
      invocation_id: "invocation",
      duration_ms: 100,
      exit_code: 3,
      target_patterns: ["//..."],
      git_branch: "main",
      git_commit_sha: "abcdef",
      started_at: ~N[2026-09-04 12:00:00],
      finished_at: ~N[2026-09-04 12:00:01],
      is_ci: true
    }
  end

  defp result(target_label, status, duration_ms, junit_content, opts \\ []) do
    %{
      target_label: target_label,
      status: status,
      duration_ms: duration_ms,
      run: Keyword.get(opts, :run, 0),
      shard: 0,
      attempt: Keyword.get(opts, :attempt, 1),
      is_ci: true,
      junit_content: junit_content
    }
  end
end
