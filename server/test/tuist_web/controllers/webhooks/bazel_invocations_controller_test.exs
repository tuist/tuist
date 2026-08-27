defmodule TuistWeb.Webhooks.BazelInvocationsControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use Mimic

  import Ecto.Query

  alias Tuist.Bazel.Invocation
  alias Tuist.ClickHouseRepo
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  @cache_api_key "test-cache-api-key"

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture(preload: [:account])

    project =
      ProjectsFixtures.project_fixture(
        account_id: user.account.id,
        build_system: :bazel
      )

    stub(Tuist.Environment, :cache_api_key, fn -> @cache_api_key end)

    %{conn: conn, project: project}
  end

  describe "POST /webhooks/bazel-invocations" do
    test "stores completed Bazel invocations with a valid signature", %{conn: conn, project: project} do
      body = %{
        "events" => [
          %{
            "account_handle" => project.account.name,
            "project_handle" => project.name,
            "invocation_id" => "invocation-1",
            "command" => "test",
            "status" => "success",
            "exit_code" => 0,
            "started_at_ms" => 1_700_000_000_000,
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
        |> post(~p"/webhooks/bazel-invocations", json_body)

      assert json_response(conn, 202) == %{}

      [invocation] =
        ClickHouseRepo.all(from(i in Invocation, where: i.project_id == ^project.id))

      assert invocation.invocation_id == "invocation-1"
      assert invocation.command == "test"
      assert invocation.status == "success"
      assert invocation.exit_code == 0
      assert invocation.duration_ms == 15_000
      assert invocation.cache_endpoint == "cache.tuist.dev"
    end

    test "does not store invalid invocation payloads", %{conn: conn, project: project} do
      body = %{
        "events" => [
          %{
            "account_handle" => project.account.name,
            "project_handle" => project.name,
            "invocation_id" => "invocation-1",
            "command" => "build",
            "status" => "unknown",
            "exit_code" => 0,
            "started_at_ms" => 1_700_000_000_000,
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
        |> post(~p"/webhooks/bazel-invocations", json_body)

      assert json_response(conn, 202) == %{}
      assert ClickHouseRepo.all(from(i in Invocation, where: i.project_id == ^project.id)) == []
    end
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
