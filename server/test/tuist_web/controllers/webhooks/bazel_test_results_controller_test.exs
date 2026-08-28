defmodule TuistWeb.Webhooks.BazelTestResultsControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use Mimic

  import Ecto.Query

  alias Tuist.Bazel.TestResult
  alias Tuist.ClickHouseRepo
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  @cache_api_key "test-cache-api-key"

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture(preload: [:account])
    project = ProjectsFixtures.project_fixture(account_id: user.account.id, build_system: :bazel)
    stub(Tuist.Environment, :cache_api_key, fn -> @cache_api_key end)
    %{conn: conn, project: project}
  end

  test "stores Bazel test-target results with a valid signature", %{conn: conn, project: project} do
    body = %{
      "events" => [
        %{
          "account_handle" => project.account.name,
          "project_handle" => project.name,
          "invocation_id" => "invocation-1",
          "target_label" => "//App:AppTests",
          "status" => "flaky",
          "duration_ms" => 1_500,
          "attempt_count" => 2,
          "finished_at_ms" => 1_700_000_015_000
        }
      ]
    }

    {json_body, signature} = sign_request(body)

    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> put_req_header("x-cache-signature", signature)
      |> put_req_header("x-cache-endpoint", "cache.tuist.dev")
      |> post(~p"/webhooks/bazel-test-results", json_body)

    assert json_response(conn, 202) == %{}

    [test_result] =
      ClickHouseRepo.all(from(test_result in TestResult, where: test_result.project_id == ^project.id))

    assert test_result.target_label == "//App:AppTests"
    assert test_result.status == "flaky"
    assert test_result.duration_ms == 1_500
    assert test_result.attempt_count == 2
    assert test_result.cache_endpoint == "cache.tuist.dev"
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
