defmodule Tuist.BazelIngestionTest do
  use ExUnit.Case, async: true
  use Oban.Testing, repo: Tuist.Repo

  alias Ecto.Adapters.SQL.Sandbox
  alias Tuist.Bazel
  alias Tuist.Bazel.TestInvocation
  alias Tuist.Bazel.TestResult
  alias Tuist.Bazel.Workers.ProcessTestInvocationWorker
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  setup do
    Sandbox.checkout(Repo)
  end

  test "bounds accumulated artifact bytes and accounts for replacements" do
    project = ProjectsFixtures.project_fixture(build_system: :bazel)
    attrs = result_attrs(project.id, "first")

    assert :ok = Bazel.stage_test_result(attrs, 10)
    assert Repo.one!(TestInvocation).artifact_bytes == 5

    assert :ok = Bazel.stage_test_result(%{attrs | log_content: "second"}, 10)
    assert Repo.one!(TestInvocation).artifact_bytes == 6
    assert Repo.one!(TestResult).log_content == "second"

    assert {:error, :artifact_limit_exceeded} =
             Bazel.stage_test_result(%{attrs | attempt: 2, log_content: "12345"}, 10)

    assert Repo.one!(TestInvocation).artifact_bytes == 6
    assert Repo.aggregate(TestResult, :count) == 1
  end

  test "a completion retry does not reopen a processed invocation" do
    project = ProjectsFixtures.project_fixture(build_system: :bazel)
    attrs = result_attrs(project.id, "test output")

    assert :ok = Bazel.stage_test_result(attrs)
    test_invocation = Repo.one!(TestInvocation)
    Bazel.delete_test_results(project.id, attrs.invocation_id)
    assert {:ok, _test_invocation} = Bazel.mark_test_invocation_processed(test_invocation)

    assert {:ok, :already_processed} = Bazel.complete_test_invocation(project.id, attrs.invocation_id)
    assert :ok = Bazel.stage_test_result(attrs)

    assert Repo.one!(TestInvocation).state == "processed"
    assert Repo.aggregate(TestResult, :count) == 0
    assert all_enqueued(worker: ProcessTestInvocationWorker) == []
  end

  test "completion moves an invocation to the dedicated processing queue" do
    project = ProjectsFixtures.project_fixture(build_system: :bazel)

    assert {:ok, %Oban.Job{queue: "process_bazel_tests"}} =
             Bazel.complete_test_invocation(project.id, "invocation-1")

    assert Repo.one!(TestInvocation).state == "pending"

    assert_enqueued(
      worker: ProcessTestInvocationWorker,
      queue: :process_bazel_tests,
      args: %{"project_id" => project.id, "invocation_id" => "invocation-1"}
    )
  end

  test "deletes expired staging records in bounded batches" do
    project = ProjectsFixtures.project_fixture(build_system: :bazel)
    old = DateTime.add(DateTime.utc_now(), -100, :day)

    for attempt <- 1..3 do
      assert :ok = Bazel.stage_test_result(%{result_attrs(project.id, "x") | attempt: attempt})
    end

    Repo.update_all(TestResult, set: [inserted_at: old])
    Repo.update_all(TestInvocation, set: [inserted_at: old])

    assert Bazel.delete_expired_test_ingestion_records(DateTime.utc_now(), 1) == 1
    assert Repo.aggregate(TestResult, :count) == 2
    assert Repo.aggregate(TestInvocation, :count) == 1

    assert Bazel.delete_expired_test_ingestion_records(DateTime.utc_now(), 1) == 1
    assert Repo.aggregate(TestResult, :count) == 1
    assert Repo.aggregate(TestInvocation, :count) == 1

    assert Bazel.delete_expired_test_ingestion_records(DateTime.utc_now(), 1) == 2
    assert Repo.aggregate(TestResult, :count) == 0
    assert Repo.aggregate(TestInvocation, :count) == 0
  end

  defp result_attrs(project_id, log_content) do
    %{
      project_id: project_id,
      invocation_id: "invocation-1",
      target_label: "//App:AppTests",
      run: 0,
      shard: 0,
      attempt: 1,
      status: "success",
      duration_ms: 100,
      started_at: ~U[2026-09-04 12:00:00Z],
      cached: false,
      is_ci: false,
      sequence_number: 1,
      log_digest: String.duplicate("a", 64),
      log_content: log_content
    }
  end
end
