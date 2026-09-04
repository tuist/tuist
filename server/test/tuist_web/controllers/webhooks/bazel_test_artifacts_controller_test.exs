defmodule TuistWeb.Webhooks.BazelTestArtifactsControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  import Ecto.Query

  alias Tuist.Bazel.TestInvocation
  alias Tuist.Bazel.TestResult
  alias Tuist.Bazel.TestSummary
  alias Tuist.Bazel.Workers.ProcessTestInvocationWorker
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  @cache_api_key "test-cache-api-key"

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture(preload: [:account])
    project = ProjectsFixtures.project_fixture(account_id: user.account.id, build_system: :bazel)
    stub(Tuist.Environment, :cache_api_key, fn -> @cache_api_key end)

    %{conn: conn, project: project}
  end

  test "durably stores a bounded result until the invocation finishes", %{
    conn: conn,
    project: project
  } do
    report = "<testsuite><testcase>"

    body =
      test_result_body(project, [
        artifact("junit", report, "b"),
        artifact("log", "secret=top-secret\ntest output\n", "c")
      ])

    assert json_response(post_signed(conn, body), 202) == %{}

    assert %TestResult{
             invocation_id: "invocation-1",
             target_label: "//App:AppTests",
             status: "failure",
             duration_ms: 1_234,
             cached: true,
             is_ci: true,
             sequence_number: 42,
             junit_content: ^report,
             log_content: "secret=top-secret\ntest output\n"
           } = Repo.one!(from(TestResult))

    assert %TestInvocation{
             invocation_id: "invocation-1",
             state: "collecting",
             test_run_id: test_run_id
           } = Repo.one!(from(TestInvocation))

    assert is_binary(test_run_id)
    assert all_enqueued(worker: ProcessTestInvocationWorker) == []
  end

  test "retries remain idempotent and refresh the pending invocation", %{conn: conn, project: project} do
    first = test_result_body(project, [artifact("log", "first", "b")])
    second = first |> put_in(["artifacts"], [artifact("log", "second", "c")]) |> Map.put("status", "success")

    assert json_response(post_signed(conn, first), 202) == %{}
    first_invocation = Repo.one!(from(TestInvocation))

    assert json_response(post_signed(conn, second), 202) == %{}

    assert Repo.aggregate(TestResult, :count) == 1
    assert Repo.aggregate(TestInvocation, :count) == 1
    assert Repo.one!(from(TestResult)).log_content == "second"
    assert Repo.one!(from(TestResult)).status == "success"
    assert Repo.one!(from(TestInvocation)).test_run_id == first_invocation.test_run_id
    assert Repo.one!(from(TestInvocation)).state == "collecting"
    assert all_enqueued(worker: ProcessTestInvocationWorker) == []
  end

  test "accepts results before the ClickHouse invocation exists", %{conn: conn, project: project} do
    body = test_result_body(project, [artifact("log", "test output", "b")])

    assert json_response(post_signed(conn, body), 202) == %{}
    assert Repo.aggregate(TestResult, :count) == 1
  end

  test "durably stores Bazel's target summary", %{conn: conn, project: project} do
    body = %{
      "event_kind" => "test_summary",
      "account_handle" => project.account.name,
      "project_handle" => project.name,
      "invocation_id" => "invocation-1",
      "target_label" => "//App:AppTests",
      "status" => "flaky",
      "total_run_count" => 3,
      "total_num_cached" => 1,
      "duration_ms" => 4_321,
      "started_at_ms" => 1_788_350_400_000,
      "finished_at_ms" => 1_788_350_405_000
    }

    assert json_response(post_signed(conn, body), 202) == %{}

    assert %TestSummary{
             status: "flaky",
             total_run_count: 3,
             total_num_cached: 1,
             duration_ms: 4_321,
             target_label: "//App:AppTests"
           } = Repo.one!(from(TestSummary))
  end

  test "accepts the invocation-finished event after queued test diagnostics", %{
    conn: conn,
    project: project
  } do
    result = test_result_body(project, [artifact("log", "test output", "b")])
    assert json_response(post_signed(conn, result), 202) == %{}
    test_run_id = Repo.one!(from(TestInvocation)).test_run_id

    finished = %{
      "event_kind" => "invocation_finished",
      "account_handle" => project.account.name,
      "project_handle" => project.name,
      "invocation_id" => "invocation-1"
    }

    assert json_response(post_signed(conn, finished), 202) == %{}

    assert %TestInvocation{state: "pending", test_run_id: ^test_run_id} =
             Repo.one!(from(TestInvocation))

    assert_enqueued(
      worker: ProcessTestInvocationWorker,
      args: %{"project_id" => project.id, "invocation_id" => "invocation-1"}
    )
  end

  test "rejects invalid UTF-8 before persistence", %{conn: conn, project: project} do
    body = test_result_body(project, [artifact("junit", <<255, 254>>, "b")])

    assert json_response(post_signed(conn, body), 400) == %{"error" => "Invalid Bazel test event"}
    assert Repo.aggregate(TestResult, :count) == 0
  end

  test "rejects results for a non-Bazel project", %{conn: conn, project: project} do
    xcode_project =
      ProjectsFixtures.project_fixture(account_id: project.account_id, build_system: :xcode)

    body = test_result_body(xcode_project, [artifact("log", "test output", "b")])

    assert json_response(post_signed(conn, body), 400) == %{"error" => "Invalid Bazel test event"}
  end

  defp test_result_body(project, artifacts) do
    %{
      "event_kind" => "test_result",
      "account_handle" => project.account.name,
      "project_handle" => project.name,
      "invocation_id" => "invocation-1",
      "target_label" => "//App:AppTests",
      "run" => 0,
      "shard" => 0,
      "attempt" => 1,
      "status" => "failure",
      "duration_ms" => 1_234,
      "started_at_ms" => 1_788_350_400_000,
      "cached" => true,
      "is_ci" => true,
      "sequence_number" => 42,
      "artifacts" => artifacts
    }
  end

  defp artifact(kind, content, digest_character) do
    %{
      "artifact_kind" => kind,
      "digest" => String.duplicate(digest_character, 64),
      "content_base64" => Base.encode64(content)
    }
  end

  defp post_signed(conn, body) do
    json_body = JSON.encode!(body)

    signature =
      :hmac
      |> :crypto.mac(:sha256, @cache_api_key, json_body)
      |> Base.encode16(case: :lower)

    conn
    |> put_req_header("content-type", "application/json")
    |> put_req_header("x-cache-signature", signature)
    |> put_req_header("x-cache-endpoint", "cache.tuist.dev")
    |> post(~p"/webhooks/bazel-test-artifacts", json_body)
  end
end
