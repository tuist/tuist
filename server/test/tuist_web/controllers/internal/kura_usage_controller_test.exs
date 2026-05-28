defmodule TuistWeb.Internal.KuraUsageControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.ClickHouseRepo
  alias Tuist.Environment
  alias Tuist.Kura.UsageEvent
  alias Tuist.OAuth.Clients
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  setup :set_mimic_from_context

  setup do
    stub(Environment, :kura_control_plane_configured?, fn -> true end)
    stub(Environment, :kura_control_plane_client_id, fn -> "kura-control-plane" end)
    stub(Environment, :kura_control_plane_client_secret, fn -> "kura-secret" end)

    stub(Clients, :get_client, fn "kura-control-plane" ->
      %Boruta.Oauth.Client{
        id: "kura-control-plane",
        secret: "kura-secret",
        supported_grant_types: ["introspect", "kura_usage"]
      }
    end)

    :ok
  end

  test "persists usage events with account and project mapping", %{conn: conn} do
    account = AccountsFixtures.organization_fixture(name: "acme").account
    project = ProjectsFixtures.project_fixture(account: account, name: "ios")
    authorization = "Basic " <> Base.encode64("kura-control-plane:kura-secret")

    conn =
      conn
      |> put_req_header("authorization", authorization)
      |> post("/_internal/kura/usage", %{
        "schema_version" => 1,
        "node_id" => "kura-0",
        "region" => "eu-central",
        "events" => [
          %{
            "event_id" => "event-1",
            "tenant_id" => "acme",
            "namespace_id" => "ios",
            "node_id" => "kura-0",
            "region" => "eu-central",
            "traffic_plane" => "public",
            "direction" => "egress",
            "operation" => "download",
            "protocol" => "http",
            "artifact_kind" => "xcode",
            "bytes" => 123,
            "request_count" => 2,
            "window_start_unix_seconds" => 1_774_438_400,
            "window_seconds" => 60
          }
        ]
      })

    assert %{"accepted" => 1} = json_response(conn, 202)

    assert [
             %UsageEvent{
               event_id: "event-1",
               account_id: account_id,
               project_id: project_id,
               bytes: 123,
               request_count: 2
             }
           ] = ClickHouseRepo.all(UsageEvent)

    assert account_id == account.id
    assert project_id == project.id
  end

  test "rejects missing credentials", %{conn: conn} do
    conn = post(conn, "/_internal/kura/usage", %{"schema_version" => 1, "events" => []})

    assert %{"error" => "unauthorized"} = json_response(conn, 401)
  end
end
