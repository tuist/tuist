defmodule Tuist.OAuth2.PinnedHTTPTest do
  # Connection-level behavior shared with `Tuist.OIDC.JWKSClient` is covered by
  # its tests; these cover what the MCP OAuth client adds on top.
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.OAuth2.PinnedHTTP

  @conn :mint_conn
  @ref :request_ref

  defp stub_connection(batches) do
    parent = self()
    {:ok, agent} = Agent.start_link(fn -> batches end)

    stub(Mint.HTTP, :connect, fn :https, _address, _port, _opts -> {:ok, @conn} end)

    stub(Mint.HTTP, :request, fn @conn, method, path, headers, body ->
      send(parent, {:request, method, path, headers, body})
      {:ok, @conn, @ref}
    end)

    stub(Mint.HTTP, :recv, fn @conn, 0, _timeout ->
      send(parent, :recv)
      {:ok, @conn, Agent.get_and_update(agent, fn [batch | rest] -> {batch, rest} end)}
    end)

    stub(Mint.HTTP, :close, fn @conn ->
      send(parent, :closed)
      {:ok, @conn}
    end)
  end

  test "sends a request body and returns non-200 responses with their bounded body" do
    stub_connection([
      [{:status, @ref, 400}, {:headers, @ref, []}, {:data, @ref, ~s({"error":"invalid_grant"})}, {:done, @ref}]
    ])

    assert {:ok, %{status: 400, body: ~s({"error":"invalid_grant"})}} =
             PinnedHTTP.request("POST", "https://203.0.113.10/token", body: "grant_type=refresh_token")

    assert_receive {:request, "POST", "/token", [], "grant_type=refresh_token"}
    assert_receive :closed
  end

  test "headers_only returns at the headers without reading an endless body" do
    # A second batch would only be read if the client kept receiving.
    stub_connection([
      [{:status, @ref, 401}, {:headers, @ref, [{"www-authenticate", ~s(Bearer realm="mcp")}]}],
      [{:data, @ref, "event: message\n"}]
    ])

    assert {:ok, %{status: 401, headers: [{"www-authenticate", ~s(Bearer realm="mcp")}], body: ""}} =
             PinnedHTTP.request("POST", "https://203.0.113.10/mcp", headers_only: true)

    assert_receive :recv
    refute_receive :recv
    assert_receive :closed
  end

  test "enforces a caller-supplied body limit" do
    stub_connection([[{:status, @ref, 200}, {:headers, @ref, []}, {:data, @ref, String.duplicate("a", 11)}]])

    assert {:error, :response_too_large} =
             PinnedHTTP.request("GET", "https://203.0.113.10/metadata", max_body_bytes: 10)

    assert_receive :closed
  end
end
