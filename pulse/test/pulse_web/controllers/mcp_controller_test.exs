defmodule PulseWeb.MCPControllerTest do
  use PulseWeb.ConnCase, async: true

  alias Pulse.Auth
  alias Pulse.Auth.SharedSecret
  alias Pulse.Record.MetricSample
  alias Pulse.Storage
  alias Pulse.Storage.Memory
  alias Pulse.Test.MCPMessages

  test "tool discovery separates query and alert mutation annotations", %{conn: conn} do
    response = request(conn, "tools/list", %{})
    tools = response["result"]["tools"]

    queries =
      Enum.filter(
        tools,
        &(String.starts_with?(&1["name"], "query_") or
            &1["name"] in ~w(list_error_issues list_error_changes list_indexed_error_issues))
      )

    assert length(queries) == 9
    assert Enum.all?(queries, &(&1["annotations"]["readOnlyHint"] == true))
    create = Enum.find(tools, &(&1["name"] == "create_alert_rule"))
    assert create["annotations"]["readOnlyHint"] == false
    assert create["annotations"]["openWorldHint"] == true
  end

  test "malformed arguments return an explicit error without failing the request", %{conn: conn} do
    response =
      request(conn, "tools/call", %{"name" => "query_logs", "arguments" => %{"tenant" => "acme", "limit" => "bad"}})

    assert response["id"] == 1
    assert response["result"]["isError"] == true
    assert hd(response["result"]["content"])["text"] =~ "invalid_arguments"

    for arguments <- [nil, []] do
      response =
        conn
        |> post_mcp(MCPMessages.request(1, "tools/call", %{"name" => "query_logs", "arguments" => arguments}))
        |> json_response(400)

      assert response["error"]["code"] == -32_602
    end
  end

  test "every query tool fails closed without tenant credentials", %{conn: conn} do
    Pulse.Runtime.put_env(:pulse, Auth, module: SharedSecret, tokens: %{})

    for name <-
          ~w(get_trace query_logs query_metrics query_traces query_logql query_promql query_errors list_error_issues list_error_changes list_indexed_error_issues) do
      response =
        request(conn, "tools/call", %{
          "name" => name,
          "arguments" => %{"tenant" => "acme", "query" => "not a valid query"}
        })

      assert response["result"]["isError"] == true
      assert hd(response["result"]["content"])["text"] =~ "unauthorized"
    end
  end

  test "invalid patterns and excessive log metric ranges return tool errors", %{conn: conn} do
    Memory.reset()
    :ok = Storage.append(:metrics, "acme", [%MetricSample{timestamp_ns: 1, value: 1.0, labels: %{"a" => "x"}}])

    for op <- ["=~", "!~"] do
      response =
        request(conn, "tools/call", %{
          "name" => "query_metrics",
          "arguments" => %{"tenant" => "acme", "matchers" => [%{"name" => "a", "op" => op, "value" => "("}]}
        })

      assert response["result"]["isError"] == true
      assert hd(response["result"]["content"])["text"] =~ "invalid_arguments"
    end

    response =
      request(conn, "tools/call", %{
        "name" => "query_logql",
        "arguments" => %{
          "tenant" => "acme",
          "query" => ~s|rate({service="api"}[5m])|,
          "start_ts_ns" => 0,
          "end_ts_ns" => 9_000_000_000_000_000_000,
          "step_ms" => 1
        }
      })

    assert response["result"]["isError"] == true
    assert hd(response["result"]["content"])["text"] =~ "too_many_steps"
  end

  test "tenant authorization precedes query argument validation", %{conn: conn} do
    Pulse.Runtime.put_env(:pulse, Auth, module: SharedSecret, tokens: %{})

    for name <-
          ~w(get_trace query_logs query_metrics query_traces query_logql query_promql query_errors list_error_issues list_error_changes list_indexed_error_issues) do
      response =
        request(conn, "tools/call", %{
          "name" => name,
          "arguments" => %{"tenant" => "acme", "start_ts_ns" => "bad", "query" => 1}
        })

      assert response["result"]["isError"] == true
      assert hd(response["result"]["content"])["text"] =~ "unauthorized"
    end
  end

  defp request(conn, method, params) do
    conn
    |> post_mcp(MCPMessages.request(1, method, params))
    |> json_response(200)
  end

  defp post_mcp(conn, message) do
    method = message["method"]
    name = get_in(message, ["params", "name"])

    conn
    |> put_req_header("content-type", "application/json")
    |> put_req_header("accept", "application/json, text/event-stream")
    |> put_req_header("mcp-protocol-version", MCPMessages.version())
    |> put_req_header("mcp-method", method)
    |> then(&if is_binary(name), do: put_req_header(&1, "mcp-name", name), else: &1)
    |> post("/mcp", JSON.encode!(message))
  end
end
