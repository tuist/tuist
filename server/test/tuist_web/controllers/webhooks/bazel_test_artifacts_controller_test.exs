defmodule TuistWeb.Webhooks.BazelTestArtifactsControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use Mimic

  import Ecto.Query

  alias Tuist.Bazel
  alias Tuist.Bazel.InvocationLog
  alias Tuist.ClickHouseRepo
  alias Tuist.Tests.Test
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  @cache_api_key "test-cache-api-key"

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture(preload: [:account])
    project = ProjectsFixtures.project_fixture(account_id: user.account.id, build_system: :bazel)
    stub(Tuist.Environment, :cache_api_key, fn -> @cache_api_key end)

    create_bazel_context(project)
    %{conn: conn, project: project}
  end

  test "stores a signed test log once and sanitizes it", %{conn: conn, project: project} do
    body = artifact_body(project, "log", "secret=top-secret\ntest output\n")
    {json_body, signature} = sign_request(body)

    request = fn ->
      conn
      |> put_req_header("content-type", "application/json")
      |> put_req_header("x-cache-signature", signature)
      |> put_req_header("x-cache-endpoint", "cache.tuist.dev")
      |> post(~p"/webhooks/bazel-test-artifacts", json_body)
    end

    assert json_response(request.(), 202) == %{}
    assert json_response(request.(), 202) == %{}

    [log] =
      ClickHouseRepo.all(
        from(log in InvocationLog,
          where: log.project_id == ^project.id and log.invocation_id == "invocation-1"
        )
      )

    assert log.message =~ "[Bazel test log for //App:AppTests]"
    assert log.message =~ "secret=<REDACTED>"
    refute log.message =~ "top-secret"
  end

  test "asks Kura to retry while the matching invocation is not available", %{conn: conn, project: project} do
    body = project |> artifact_body("log", "test output\n") |> Map.put("invocation_id", "not-yet-persisted")
    {json_body, signature} = sign_request(body)

    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> put_req_header("x-cache-signature", signature)
      |> put_req_header("x-cache-endpoint", "cache.tuist.dev")
      |> post(~p"/webhooks/bazel-test-artifacts", json_body)

    assert json_response(conn, 409) == %{"error" => "Bazel invocation is not ready"}
  end

  test "parses a signed JUnit report without reading Kura", %{conn: conn, project: project} do
    report = """
    <testsuite name="AppTests">
      <testcase name="works" time="0.012" />
    </testsuite>
    """

    body = project |> artifact_body("junit", report) |> Map.put("digest", String.duplicate("c", 64))
    {json_body, signature} = sign_request(body)

    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> put_req_header("x-cache-signature", signature)
      |> put_req_header("x-cache-endpoint", "cache.tuist.dev")
      |> post(~p"/webhooks/bazel-test-artifacts", json_body)

    assert json_response(conn, 202) == %{}

    [test] =
      ClickHouseRepo.all(
        from(test in Test,
          where: test.project_id == ^project.id and test.bazel_invocation_id == "invocation-1"
        )
      )

    assert test.scheme == "//App:AppTests"
  end

  defp create_bazel_context(project) do
    finished_at = ~N[2026-09-02 12:00:00]

    Bazel.create_invocations([
      %{
        invocation_id: "invocation-1",
        command: "test",
        status: "success",
        exit_code: 0,
        started_at: NaiveDateTime.add(finished_at, -1, :second),
        finished_at: finished_at,
        duration_ms: 1_000,
        target_patterns: ["//App:AppTests"],
        project_id: project.id,
        account_handle: project.account.name,
        project_handle: project.name,
        cache_endpoint: ""
      }
    ])
  end

  defp artifact_body(project, artifact_kind, content) do
    %{
      "account_handle" => project.account.name,
      "project_handle" => project.name,
      "invocation_id" => "invocation-1",
      "target_label" => "//App:AppTests",
      "action_digest" => String.duplicate("a", 64),
      "artifact_kind" => artifact_kind,
      "digest" => String.duplicate("b", 64),
      "content_base64" => Base.encode64(content)
    }
  end

  defp sign_request(body) do
    json_body = JSON.encode!(body)

    signature =
      :hmac
      |> :crypto.mac(:sha256, @cache_api_key, json_body)
      |> Base.encode16(case: :lower)

    {json_body, signature}
  end
end
