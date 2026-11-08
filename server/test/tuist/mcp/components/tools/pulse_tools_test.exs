defmodule Tuist.MCP.Components.Tools.PulseToolsTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Accounts
  alias Tuist.Accounts.AccountToken
  alias Tuist.Accounts.AuthenticatedAccount
  alias Tuist.Environment
  alias Tuist.MCP.Components.Tools.GetPulseAnalytics
  alias Tuist.MCP.Components.Tools.GetPulseErrorEvent
  alias Tuist.MCP.Components.Tools.GetPulseErrorIssue
  alias Tuist.MCP.Components.Tools.QueryPulse
  alias Tuist.Pulse
  alias TuistTestSupport.Fixtures.AccountsFixtures

  setup do
    user = AccountsFixtures.user_fixture()
    organization = AccountsFixtures.organization_fixture(creator: user)
    account = organization.account
    stub(Environment, :pulse_config, fn -> [account_id: account.id] end)
    stub(Tuist.FeatureFlags, :pulse_enabled?, fn _ -> true end)

    %{
      user: user,
      organization: organization,
      account: account,
      conn: %Plug.Conn{assigns: %{current_user: user}},
      args: %{"account_handle" => account.name, "signal" => "logs"}
    }
  end

  defp result do
    %{
      rows: [
        %{"timestamp" => "123", "service" => "server", "level" => "error", "message" => "timeout", "trace_id" => "abc"}
      ],
      series: [],
      warnings: [],
      meta: %{
        "page" => 2,
        "page_size" => 1,
        "total_count" => 3,
        "total_pages" => 3,
        "end_at" => "2026-10-01T12:00:00Z",
        "has_next_page" => true,
        "has_previous_page" => true
      }
    }
  end

  test "passes table arguments unchanged and validates nonempty structured content", ctx do
    params = %{
      "page" => 2,
      "page_size" => 1,
      "sort_by" => "service",
      "sort_order" => "asc",
      "search" => "time",
      "service" => "server",
      "end_at" => "2026-10-01T12:00:00Z"
    }

    expect(Pulse, :query, fn user, account, "logs", ^params ->
      assert user.id == ctx.user.id
      assert account.id == ctx.account.id
      {:ok, result()}
    end)

    assert %{"structuredContent" => %{"rows" => [%{"message" => "timeout"}], "meta" => %{"page" => 2}}} =
             QueryPulse.call(ctx.conn, Map.merge(ctx.args, params))
  end

  test "rejects invalid inputs and analytics table parameters before reads", ctx do
    reject(&Pulse.query/4)
    reject(&Pulse.analytics/4)

    for params <- [
          %{"page" => 0},
          %{"page_size" => 101},
          %{"page" => "2"},
          %{"sort_order" => "other"},
          %{"tenant" => "other"}
        ] do
      assert %{"isError" => true} = QueryPulse.call(ctx.conn, Map.merge(ctx.args, params))
    end

    assert %{"isError" => true} = GetPulseAnalytics.call(ctx.conn, Map.put(ctx.args, "query", "up"))
  end

  test "analytics forwards only supplied range and preserves null measurements", ctx do
    expect(Pulse, :analytics, fn _, _, "logs", %{"range" => "6h"} ->
      {:ok,
       %{
         widgets: [%{id: "entries", unit: :count, value: 0, previous_value: nil, points: [[123, nil], [124, 0]]}],
         warnings: []
       }}
    end)

    assert %{"structuredContent" => %{"widgets" => [%{"previous_value" => nil, "value" => 0}]}} =
             GetPulseAnalytics.call(ctx.conn, Map.put(ctx.args, "range", "6h"))
  end

  test "detail tools preserve issue/event scoping and projected exception shapes", ctx do
    issue = %{
      "issue_id" => "issue",
      "project" => "server",
      "service" => "api",
      "title" => "Error",
      "count" => 1,
      "first_seen_ns" => 123,
      "last_seen_ns" => 123,
      "latest_event_id" => "event"
    }

    event = %{
      "event_id" => "event",
      "issue_id" => "issue",
      "timestamp_ns" => "123",
      "timestamp" => "123",
      "project" => "server",
      "service" => "api",
      "level" => nil,
      "environment" => nil,
      "release" => nil,
      "title" => "Error",
      "exception" => %{},
      "exceptions" => [
        %{
          "type" => "RuntimeError",
          "value" => "failed",
          "frames" => [
            %{
              "filename" => "server.ex",
              "module" => nil,
              "function" => "run",
              "lineno" => 42,
              "in_app" => true
            }
          ]
        }
      ]
    }

    meta = result().meta
    occurrence_series = Enum.map(0..59, fn bucket -> [bucket * 60, if(bucket == 0, do: 1, else: 0)] end)

    args =
      ctx.args
      |> Map.delete("signal")
      |> Map.merge(%{"issue_id" => "issue", "project" => "server", "environment" => "production", "page" => 2})

    expect(Pulse, :error_issue, fn _, _, "issue", %{"project" => "server", "environment" => "production", "page" => 2} ->
      {:ok,
       %{
         issue: issue,
         latest_event: event,
         occurrence_series: occurrence_series,
         events: [event],
         meta: meta,
         warnings: []
       }}
    end)

    assert %{
             "structuredContent" => %{
               "events" => [^event],
               "latest_event" => ^event,
               "occurrence_series" => ^occurrence_series
             }
           } =
             GetPulseErrorIssue.call(ctx.conn, args)

    args = args |> Map.delete("page") |> Map.put("event_id", "event")

    expect(Pulse, :error_event, fn _, _, "issue", "event", %{"project" => "server", "environment" => "production"} ->
      {:ok, %{event: event, warnings: []}}
    end)

    assert %{"structuredContent" => %{"event" => ^event}} = GetPulseErrorEvent.call(ctx.conn, args)
    assert %{"isError" => true} = GetPulseErrorEvent.call(ctx.conn, Map.put(args, "page", 1))
  end

  test "membership is persisted, rechecked after removal and independent of public visibility", ctx do
    {:ok, _account} = Accounts.update_account(ctx.account, %{visibility: :public})
    member = AccountsFixtures.user_fixture()
    :ok = Accounts.add_user_to_organization(member, ctx.organization, role: :viewer)
    conn = %Plug.Conn{assigns: %{current_user: member}}
    stub(Pulse, :query, fn _, _, _, _ -> {:ok, result()} end)
    assert %{"structuredContent" => _} = QueryPulse.call(conn, ctx.args)
    Accounts.remove_user_from_organization(member, ctx.organization)
    assert %{"isError" => true} = QueryPulse.call(conn, ctx.args)
    outsider = AccountsFixtures.user_fixture()
    assert %{"isError" => true} = QueryPulse.call(%Plug.Conn{assigns: %{current_user: outsider}}, ctx.args)
  end

  test "WebMCP account scope and configured organization remain mandatory", ctx do
    reject(&Pulse.query/4)
    conn = %{ctx.conn | assigns: Map.put(ctx.conn.assigns, :mcp_account_scope, %{id: ctx.account.id + 1})}
    assert %{"isError" => true} = QueryPulse.call(conn, ctx.args)
    stub(Environment, :pulse_config, fn -> [account_id: ctx.account.id + 1] end)
    assert %{"isError" => true} = QueryPulse.call(ctx.conn, ctx.args)
  end

  test "associated users cannot upgrade under-scoped or userless account credentials", ctx do
    reject(&Pulse.query/4)

    for scopes <- [[], ["project:builds:read"], ["account:read"]] do
      subject = %AuthenticatedAccount{account: ctx.account, scopes: scopes}
      conn = %{ctx.conn | assigns: Map.put(ctx.conn.assigns, :current_subject, subject)}
      assert %{"isError" => true} = QueryPulse.call(conn, ctx.args)
    end

    subject = %AuthenticatedAccount{account: ctx.account, scopes: [AccountToken.mcp_scope()]}
    assert %{"isError" => true} = QueryPulse.call(%Plug.Conn{assigns: %{current_subject: subject}}, ctx.args)
  end

  test "user-associated MCP credentials retain the framework's account read policy", ctx do
    subject = %AuthenticatedAccount{account: ctx.user.account, scopes: [AccountToken.mcp_scope()], issued_by: ctx.user}
    conn = %{ctx.conn | assigns: Map.put(ctx.conn.assigns, :current_subject, subject)}
    expect(Pulse, :query, fn _, _, _, _ -> {:ok, result()} end)
    assert %{"structuredContent" => _} = QueryPulse.call(conn, ctx.args)
  end

  test "domain errors become safe tool errors", ctx do
    for reason <- [
          :invalid_params,
          :invalid_query,
          :not_found,
          :query_result_limit,
          :forbidden,
          :not_configured,
          :rate_limited,
          :upstream_error,
          :malformed_response,
          :timeout
        ] do
      stub(Pulse, :query, fn _, _, _, _ -> {:error, reason} end)
      assert %{"isError" => true, "content" => [%{"text" => text}]} = QueryPulse.call(ctx.conn, ctx.args)
      refute text =~ "secret"
    end
  end
end
