defmodule Atlas.Grafana.LokiTest do
  use ExUnit.Case, async: true

  alias Atlas.Grafana.Loki

  @now ~U[2026-08-26 10:00:00Z]

  defp options(request) do
    [
      base_url: "https://logs.grafana.test/",
      username: "986520",
      token: "token",
      now: @now,
      request: request
    ]
  end

  describe "mcp_usage/2" do
    test "aggregates successful requests and returns the latest timestamp" do
      parent = self()

      request = fn req ->
        send(parent, {:request, req})

        case URI.parse(to_string(req.url)).path do
          "/loki/api/v1/query" ->
            query = req.options[:params][:query]
            count = if query =~ "[24h]", do: "2", else: "9"

            {:ok, %Req.Response{status: 200, body: %{"data" => %{"result" => [%{"value" => ["0", count]}]}}}}

          "/loki/api/v1/query_range" ->
            {:ok,
             %Req.Response{
               status: 200,
               body: %{
                 "data" => %{
                   "result" => [
                     %{"values" => [["1787736600000000000", "request completed"]]}
                   ]
                 }
               }
             }}
        end
      end

      assert {:ok, usage} = Loki.mcp_usage("acme", options(request))
      assert usage.events_last_24h == 2
      assert usage.events_last_7d == 9
      assert usage.events_prior_7d == 0
      assert usage.last_used_at == ~U[2026-08-26 09:30:00Z]

      assert_receive {:request, first}
      assert first.method == :get
      assert to_string(first.url) == "https://logs.grafana.test/loki/api/v1/query"
      assert first.options[:auth] == {:basic, "986520", "token"}
      assert first.options[:params][:query] =~ ~s(mcp_account_handle = "acme")
      assert first.options[:params][:query] =~ ~s(mcp_tool_name != "")
      assert first.options[:params][:time] == "1787738400000000000"

      assert_receive {:request, second}
      assert second.options[:params][:query] =~ "[7d]"

      assert_receive {:request, third}
      assert to_string(third.url) == "https://logs.grafana.test/loki/api/v1/query_range"
      assert third.options[:params][:start] == "1787047200000000000"
      assert third.options[:params][:end] == "1787738400000000000"
      assert third.options[:params][:limit] == 1
      assert third.options[:params][:direction] == "backward"
    end

    test "returns zeroes and no last-used date when no requests match" do
      request = fn _req -> {:ok, %Req.Response{status: 200, body: %{"data" => %{"result" => []}}}} end

      assert {:ok, usage} = Loki.mcp_usage("acme", options(request))
      assert usage.events_last_24h == 0
      assert usage.events_last_7d == 0
      assert usage.last_used_at == nil
    end

    test "treats an invalid log timestamp as no last-used date" do
      parent = self()

      request = fn req ->
        send(parent, {:request, req})

        case URI.parse(to_string(req.url)).path do
          "/loki/api/v1/query" ->
            {:ok, %Req.Response{status: 200, body: %{"data" => %{"result" => [%{"value" => ["0", "0"]}]}}}}

          "/loki/api/v1/query_range" ->
            {:ok,
             %Req.Response{status: 200, body: %{"data" => %{"result" => [%{"values" => [["invalid", "request"]]}]}}}}
        end
      end

      assert {:ok, %{last_used_at: nil}} = Loki.mcp_usage("acme", options(request))
    end

    test "returns an error when the service credentials are absent" do
      assert {:error, "Grafana Loki usage queries are not configured."} =
               Loki.mcp_usage("acme", base_url: "https://logs.grafana.test", username: nil, token: nil)
    end
  end

  describe "configured?/1" do
    test "requires a base URL, tenant username, and token" do
      assert Loki.configured?(base_url: "https://logs.grafana.test", username: "986520", token: "token")
      refute Loki.configured?(base_url: "https://logs.grafana.test", username: "986520", token: nil)
    end
  end
end
