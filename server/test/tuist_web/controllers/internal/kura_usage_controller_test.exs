defmodule TuistWeb.Internal.KuraUsageControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Boruta.Oauth.Client
  alias Tuist.ClickHouseRepo
  alias Tuist.Environment
  alias Tuist.Kura.UsageEvent
  alias Tuist.OAuth.Clients
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  setup :set_mimic_from_context

  setup do
    kura_client = %Client{
      id: "kura-control-plane",
      secret: "kura-secret",
      confidential: true,
      supported_grant_types: ["introspect", "kura_usage"],
      token_endpoint_auth_methods: ["client_secret_basic"]
    }

    stub(Environment, :kura_control_plane_configured?, fn -> true end)
    stub(Environment, :kura_control_plane_client_id, fn -> kura_client.id end)
    stub(Environment, :kura_control_plane_client_secret, fn -> kura_client.secret end)

    stub(Clients, :get_client, fn
      "kura-control-plane" -> kura_client
      _ -> nil
    end)

    {:ok, kura_client: kura_client}
  end

  defp authorization_header(client_id, client_secret) do
    "Basic " <> Base.encode64("#{client_id}:#{client_secret}")
  end

  defp build_event(overrides \\ %{}) do
    Map.merge(
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
      },
      overrides
    )
  end

  defp post_events(conn, events, opts \\ []) do
    payload =
      %{"schema_version" => 1, "node_id" => "kura-0", "region" => "eu-central", "events" => events}

    conn =
      case Keyword.get(opts, :authorization) do
        nil -> conn
        header -> put_req_header(conn, "authorization", header)
      end

    post(conn, "/_internal/kura/usage", payload)
  end

  test "persists usage events with account and project mapping", %{conn: conn, kura_client: client} do
    account = AccountsFixtures.organization_fixture(name: "acme").account
    project = ProjectsFixtures.project_fixture(account: account, name: "ios")

    conn =
      post_events(conn, [build_event()], authorization: authorization_header(client.id, client.secret))

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
    conn = post_events(conn, [])

    assert %{"error" => "unauthorized"} = json_response(conn, 401)
  end

  test "rejects wrong client_secret", %{conn: conn, kura_client: client} do
    conn = post_events(conn, [], authorization: authorization_header(client.id, "wrong-secret"))

    assert %{"error" => "unauthorized"} = json_response(conn, 401)
  end

  test "rejects unknown client_id", %{conn: conn} do
    conn = post_events(conn, [], authorization: authorization_header("not-kura", "kura-secret"))

    assert %{"error" => "unauthorized"} = json_response(conn, 401)
  end

  test "rejects when Kura control plane is not configured", %{conn: conn, kura_client: client} do
    stub(Environment, :kura_control_plane_configured?, fn -> false end)

    conn = post_events(conn, [], authorization: authorization_header(client.id, client.secret))

    assert %{"error" => "unauthorized"} = json_response(conn, 401)
  end

  test "rejects malformed payload", %{conn: conn, kura_client: client} do
    conn =
      conn
      |> put_req_header("authorization", authorization_header(client.id, client.secret))
      |> post("/_internal/kura/usage", %{"schema_version" => 2})

    assert %{"error" => "invalid_payload"} = json_response(conn, 400)
  end

  test "rejects malformed usage events", %{conn: conn, kura_client: client} do
    conn =
      post_events(conn, [build_event(%{"bytes" => "123"})], authorization: authorization_header(client.id, client.secret))

    assert %{"error" => "invalid_events"} = json_response(conn, 400)
  end
end
