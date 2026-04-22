defmodule TuistWeb.API.MetricsControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use Mimic

  alias Tuist.Accounts
  alias Tuist.Environment
  alias Tuist.Metrics
  alias Tuist.Metrics.Aggregator
  alias TuistTestSupport.Fixtures.AccountsFixtures

  setup do
    stub(Environment, :tuist_hosted?, fn -> true end)

    case GenServer.whereis(Aggregator) do
      nil -> start_supervised!(Aggregator)
      _ -> Aggregator.reset()
    end

    :ok
  end

  defp create_token(account, scopes) do
    {:ok, {_, token}} =
      Accounts.create_account_token(%{
        account: account,
        scopes: scopes,
        name: "metrics-#{System.unique_integer([:positive])}"
      })

    token
  end

  describe "GET /api/accounts/:account_handle/metrics" do
    test "returns 401 without a bearer token", %{conn: conn} do
      user = AccountsFixtures.user_fixture(preload: [:account])

      conn = get(conn, "/api/accounts/#{user.account.name}/metrics")

      assert conn.status == 401
    end

    test "returns 403 when the token is missing the metrics:read scope", %{conn: conn} do
      user = AccountsFixtures.user_fixture(preload: [:account])
      token = create_token(user.account, ["project:cache:read"])

      conn =
        conn
        |> put_req_header("authorization", "Bearer " <> token)
        |> get("/api/accounts/#{user.account.name}/metrics")

      assert conn.status == 403
      assert Jason.decode!(conn.resp_body)["message"] =~ "account:metrics:read"
    end

    test "returns 403 when authenticated as a different account", %{conn: conn} do
      user_a = AccountsFixtures.user_fixture(preload: [:account])
      user_b = AccountsFixtures.user_fixture(preload: [:account])
      token = create_token(user_a.account, ["account:metrics:read"])

      conn =
        conn
        |> put_req_header("authorization", "Bearer " <> token)
        |> get("/api/accounts/#{user_b.account.name}/metrics")

      assert conn.status == 403
    end

    test "returns prometheus text with recorded counters", %{conn: conn} do
      user = AccountsFixtures.user_fixture(preload: [:account])
      token = create_token(user.account, ["account:metrics:read"])

      Metrics.increment_counter(
        user.account.id,
        "tuist_xcode_cache_events_total",
        {"#{user.account.name}/ios", "remote_hit"},
        3
      )

      conn =
        conn
        |> put_req_header("authorization", "Bearer " <> token)
        |> get("/api/accounts/#{user.account.name}/metrics")

      assert conn.status == 200
      [content_type] = Plug.Conn.get_resp_header(conn, "content-type")
      assert content_type =~ "text/plain"
      assert content_type =~ "version=0.0.4"

      assert conn.resp_body =~ "# HELP tuist_xcode_cache_events_total"
      assert conn.resp_body =~ "# TYPE tuist_xcode_cache_events_total counter"

      assert conn.resp_body =~
               ~s(tuist_xcode_cache_events_total{project="#{user.account.name}/ios",event_type="remote_hit"} 3)
    end

    test "returns openmetrics output when the client requests it", %{conn: conn} do
      user = AccountsFixtures.user_fixture(preload: [:account])
      token = create_token(user.account, ["account:metrics:read"])

      Metrics.increment_counter(
        user.account.id,
        "tuist_xcode_cache_events_total",
        {"#{user.account.name}/ios", "miss"}
      )

      conn =
        conn
        |> put_req_header("authorization", "Bearer " <> token)
        |> put_req_header("accept", "application/openmetrics-text; version=1.0.0")
        |> get("/api/accounts/#{user.account.name}/metrics")

      assert conn.status == 200
      [content_type] = Plug.Conn.get_resp_header(conn, "content-type")
      assert content_type =~ "application/openmetrics-text"
      # OpenMetrics strips the `_total` suffix in HELP/TYPE and keeps exactly
      # one `_total` on the sample line.
      assert conn.resp_body =~ "# HELP tuist_xcode_cache_events "
      assert conn.resp_body =~ "# TYPE tuist_xcode_cache_events counter"
      assert conn.resp_body =~ ~s(tuist_xcode_cache_events_total{project=")
      refute conn.resp_body =~ "tuist_xcode_cache_events_total_total"
      assert String.ends_with?(conn.resp_body, "# EOF\n")
    end

    test "rate limits repeated scrapes from the same account", %{conn: conn} do
      user = AccountsFixtures.user_fixture(preload: [:account])
      token = create_token(user.account, ["account:metrics:read"])

      path = "/api/accounts/#{user.account.name}/metrics"

      responses =
        for _ <- 1..6 do
          conn
          |> put_req_header("authorization", "Bearer " <> token)
          |> get(path)
        end

      statuses = Enum.map(responses, & &1.status)
      # Allowed requests within the burst still succeed, later requests
      # within the same scrape interval are throttled.
      assert 200 in statuses
      assert 429 in statuses

      # The throttled response must advertise Retry-After so well-behaved
      # scrapers back off, and the body is JSON so the error surfaces in
      # scraper logs rather than being opaque.
      denied = Enum.find(responses, &(&1.status == 429))
      assert Plug.Conn.get_resp_header(denied, "retry-after") == ["10"]
      decoded = Jason.decode!(denied.resp_body)
      assert decoded["message"] =~ "Too many metric scrape requests"
    end
  end
end
