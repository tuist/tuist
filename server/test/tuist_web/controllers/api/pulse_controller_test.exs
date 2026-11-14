defmodule TuistWeb.API.PulseControllerTest do
  use ExUnit.Case, async: true
  use Mimic

  import Plug.Conn

  alias OpenApiSpex.Plug.PutApiSpec
  alias Tuist.Accounts
  alias Tuist.Accounts.Account
  alias Tuist.Accounts.AuthenticatedAccount
  alias Tuist.Accounts.User
  alias Tuist.Authorization
  alias Tuist.Pulse
  alias TuistWeb.API.PulseController, as: Controller

  setup do
    account = %Account{id: 1, name: "acme", organization_id: 2, visibility: :private}
    user = %User{id: 3}
    stub(Accounts, :get_account_by_handle, fn "acme" -> account end)
    stub(Authorization, :authorize, fn :account_dashboard_read, ^user, ^account -> :ok end)
    stub(Pulse, :authorized?, fn ^user, ^account -> true end)
    %{account: account, user: user}
  end

  defp call(action, params, assigns) do
    path = Map.merge(%{"account_handle" => "acme"}, Map.take(params, ~w(signal)))
    query = Map.drop(params, ~w(signal))
    conn = Plug.Test.conn(:get, "/?" <> URI.encode_query(query))
    conn = %{conn | path_params: path, params: Map.merge(path, query), query_params: query, body_params: %{}}
    conn = Enum.reduce(assigns, conn, fn {key, value}, conn -> assign(conn, key, value) end)

    conn
    |> PutApiSpec.call(PutApiSpec.init(module: TuistWeb.API.Spec))
    |> Controller.call(action)
  end

  test "casts pagination and preserves pinned windows, filters and sorting", ctx do
    expect(Pulse, :query, fn user, account, "logs", params ->
      assert user == ctx.user
      assert account == ctx.account

      assert params == %{
               "page" => 2,
               "page_size" => 3,
               "range" => "6h",
               "end_at" => "2026-10-01T12:00:00Z",
               "query" => "connection reset",
               "search" => "timeout",
               "service" => "server",
               "level" => "error",
               "service_op" => "contains",
               "sort_by" => "service",
               "sort_order" => "asc"
             }

      {:ok, %{rows: [], series: [], warnings: [], meta: %{}}}
    end)

    result =
      call(
        :query,
        %{
          "signal" => "logs",
          "page" => "2",
          "page_size" => "3",
          "range" => "6h",
          "end_at" => "2026-10-01T12:00:00Z",
          "query" => "connection reset",
          "search" => "timeout",
          "service" => "server",
          "service_op" => "contains",
          "level" => "error",
          "sort_by" => "service",
          "sort_order" => "asc"
        },
        current_user: ctx.user
      )

    assert result.status == 200
    assert get_resp_header(result, "cache-control") == ["private, no-store"]
  end

  test "analytics accepts only range, without table defaults", ctx do
    expect(Pulse, :analytics, fn _, _, "metrics", %{"range" => "1h"} -> {:ok, %{widgets: [], warnings: []}} end)
    assert call(:analytics, %{"signal" => "metrics"}, current_user: ctx.user).status == 200
    assert call(:analytics, %{"signal" => "metrics", "query" => "up"}, current_user: ctx.user).status == 400
  end

  test "rejects invalid and backend override parameters before querying", ctx do
    reject(&Pulse.query/4)

    for params <- [
          %{"page" => "0"},
          %{"page_size" => "101"},
          %{"sort_order" => "random"},
          %{"range" => "7d"},
          %{"tenant" => "other"},
          %{"token" => "secret"}
        ] do
      result = call(:query, Map.put(params, "signal", "logs"), current_user: ctx.user)
      assert result.status == 400
      assert get_resp_header(result, "cache-control") == ["private, no-store"]
    end

    for action <- [:query, :analytics] do
      assert call(action, %{"signal" => "errors"}, current_user: ctx.user).status == 400
    end
  end

  test "account-read denial and removed membership deny before querying", ctx do
    reject(&Pulse.query/4)
    stub(Authorization, :authorize, fn _, _, _ -> {:error, :forbidden} end)
    assert call(:query, %{"signal" => "logs"}, current_user: ctx.user).status == 403
    stub(Authorization, :authorize, fn _, _, _ -> :ok end)
    stub(Pulse, :authorized?, fn _, _ -> false end)
    assert call(:query, %{"signal" => "logs"}, current_user: ctx.user).status == 403
  end

  test "associated membership cannot upgrade unrelated scoped or userless credentials", ctx do
    reject(&Pulse.query/4)
    subject = %AuthenticatedAccount{account: ctx.account, scopes: ["project:builds:read"]}
    assert call(:query, %{"signal" => "logs"}, current_user: ctx.user, current_subject: subject).status == 403
    assert call(:query, %{"signal" => "logs"}, current_subject: subject).status == 403
    assert call(:query, %{"signal" => "logs"}, current_user: ctx.user, current_subject: %User{id: 99}).status == 403
  end

  test "maps domain failures without leaking upstream diagnostics", ctx do
    for {reason, status} <- [
          forbidden: 403,
          invalid_params: 400,
          invalid_query: 400,
          not_found: 404,
          query_result_limit: 503,
          rate_limited: 429,
          not_configured: 503,
          timeout: 503,
          malformed_response: 503,
          upstream_error: 503,
          unavailable: 503
        ] do
      stub(Pulse, :query, fn _, _, _, _ -> {:error, reason} end)
      result = call(:query, %{"signal" => "logs"}, current_user: ctx.user)
      assert result.status == status
      assert %{"message" => message} = JSON.decode!(result.resp_body)
      assert is_binary(message)
      refute message =~ "secret"
      assert get_resp_header(result, "cache-control") == ["private, no-store"]
    end
  end

  test "analytics routes resolve before signal routes and error issue routes do not exist" do
    for {path, action} <- [{"logs/analytics", :analytics}, {"logs", :query}] do
      route = Phoenix.Router.route_info(TuistWeb.Router, "GET", "/api/accounts/acme/pulse/" <> path, "localhost")
      assert route.plug == Controller
      assert route.plug_opts == action
    end

    for path <- ["errors/issues/issue/events/event", "errors/issues/issue"] do
      assert Phoenix.Router.route_info(TuistWeb.Router, "GET", "/api/accounts/acme/pulse/" <> path, "localhost") == :error
    end
  end
end
