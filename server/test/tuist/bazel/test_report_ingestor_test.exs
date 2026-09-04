defmodule Tuist.Bazel.TestReportIngestorTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Bazel.TestReportIngestor
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  setup :verify_on_exit!

  test "creates one run with independently derived modules and invocation context" do
    project = ProjectsFixtures.project_fixture(build_system: :bazel)
    test_run_id = UUIDv7.generate()

    invocation = %{
      test_run_id: test_run_id,
      invocation_id: "invocation-1",
      duration_ms: 4_000,
      exit_code: 3,
      target_patterns: ["//..."],
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
    project = ProjectsFixtures.project_fixture(build_system: :bazel)
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
      result("//App:FlakyTests", "failure", 300, failed, attempt: 1),
      result("//App:FlakyTests", "flaky", 200, passed, attempt: 2)
    ]

    expect(Tuist.Tests, :create_test, fn attrs ->
      assert attrs.is_ci
      assert attrs.scheme == "//App:FlakyTests"
      assert [%{status: "success", test_cases: [test_case]}] = attrs.test_modules
      assert test_case.status == "success"
      assert Enum.map(test_case.repetitions, & &1.status) == ["failure", "success"]
      {:ok, %{id: test_run_id}}
    end)

    assert {:ok, %{id: ^test_run_id}} = TestReportIngestor.ingest(project, invocation, results, [])
  end

  defp result(target_label, status, duration_ms, junit_content, opts \\ []) do
    %{
      target_label: target_label,
      status: status,
      duration_ms: duration_ms,
      run: 0,
      shard: 0,
      attempt: Keyword.get(opts, :attempt, 1),
      is_ci: true,
      junit_content: junit_content
    }
  end
end
