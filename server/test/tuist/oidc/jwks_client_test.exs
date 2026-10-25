defmodule Tuist.OIDC.JWKSClientTest do
  # The pool lifecycle regression observes the application's shared Finch supervisor.
  use ExUnit.Case, async: false
  use Mimic

  alias Tuist.OIDC.JWKSClient

  @conn :mint_conn
  @ref :request_ref
  @transport_opts [verify: :verify_peer, server_name_indication: ~c"keys.example"]

  defp opts(overrides \\ []) do
    Keyword.merge(
      [
        connect_options: [hostname: "keys.example", transport_opts: @transport_opts, timeout: 5_000],
        receive_timeout: 5_000,
        headers: [{"accept", "application/json"}]
      ],
      overrides
    )
  end

  defp stub_connection(batches) do
    parent = self()
    {:ok, agent} = Agent.start_link(fn -> batches end)

    stub(Mint.HTTP, :connect, fn scheme, address, port, connect_opts ->
      send(parent, {:connect, scheme, address, port, connect_opts})
      {:ok, @conn}
    end)

    stub(Mint.HTTP, :request, fn @conn, method, path, headers, body ->
      send(parent, {:request, method, path, headers, body})
      {:ok, @conn, @ref}
    end)

    stub(Mint.HTTP, :recv, fn @conn, 0, timeout ->
      send(parent, {:recv, timeout})

      case Agent.get_and_update(agent, fn [batch | rest] -> {batch, rest} end) do
        {:error, reason} -> {:error, @conn, reason, []}
        responses -> {:ok, @conn, responses}
      end
    end)

    stub(Mint.HTTP, :close, fn @conn ->
      send(parent, :closed)
      {:ok, @conn}
    end)
  end

  test "connects to the pinned IP with the original hostname over one passive HTTP/1 connection" do
    stub_connection([
      [{:status, @ref, 200}, {:headers, @ref, [{"content-type", "application/json"}]}, {:data, @ref, ~s({"keys")}],
      [{:data, @ref, ~s(: []})}, {:done, @ref}]
    ])

    assert {:ok, %{status: 200, headers: [{"content-type", "application/json"}], body: ~s({"keys": []})}} =
             JWKSClient.get("https://203.0.113.10/tenant/jwks?version=2", opts())

    assert_receive {:connect, :https, "203.0.113.10", 443, connect_opts}
    assert connect_opts[:hostname] == "keys.example"
    assert connect_opts[:protocols] == [:http1]
    assert connect_opts[:mode] == :passive
    assert connect_opts[:max_header_list_size] == 16_384
    assert connect_opts[:transport_opts][:verify] == :verify_peer
    assert connect_opts[:transport_opts][:server_name_indication] == ~c"keys.example"
    assert connect_opts[:transport_opts][:timeout] == 5_000
    assert connect_opts[:transport_opts][:inet6] == false

    assert_receive {:request, "GET", "/tenant/jwks?version=2", [{"accept", "application/json"}], nil}
    assert_receive {:recv, timeout} when timeout <= 5_000
    assert_receive :closed
    refute_receive :closed
  end

  test "uses IPv6 transport for pinned IPv6 addresses and a root path by default" do
    stub_connection([[{:status, @ref, 200}, {:headers, @ref, []}, {:done, @ref}]])

    assert {:ok, %{status: 200, body: ""}} = JWKSClient.get("https://[2001:db8::1]:8443", opts())

    assert_receive {:connect, :https, "2001:db8::1", 8443, connect_opts}
    assert connect_opts[:transport_opts][:inet6] == true
    assert_receive {:request, "GET", "/", _, nil}
    assert_receive :closed
  end

  test "skips informational responses before the final status" do
    stub_connection([
      [{:status, @ref, 100}, {:headers, @ref, []}, {:status, @ref, 200}, {:headers, @ref, []}],
      [{:data, @ref, "{}"}, {:done, @ref}]
    ])

    assert {:ok, %{status: 200, body: "{}"}} = JWKSClient.get("https://203.0.113.10/jwks", opts())
    assert_receive :closed
  end

  for status <- [204, 301, 302, 307, 404, 500] do
    test "returns any final #{status} as an error without following it" do
      stub_connection([
        [
          {:status, @ref, unquote(status)},
          {:headers, @ref, [{"location", "https://169.254.169.254/"}]},
          {:done, @ref}
        ]
      ])

      assert {:error, {:unexpected_status, unquote(status)}} = JWKSClient.get("https://203.0.113.10/jwks", opts())
      assert_receive :closed
      assert_receive {:request, "GET", "/jwks", _, nil}
      refute_receive {:request, _, _, _, _}
    end
  end

  test "limits accumulated bodies to 64 KiB" do
    stub_connection([
      [{:status, @ref, 200}, {:headers, @ref, []}, {:data, @ref, String.duplicate("a", 65_536)}],
      [{:data, @ref, "a"}, {:done, @ref}]
    ])

    assert {:error, :response_too_large} = JWKSClient.get("https://203.0.113.10/jwks", opts())
    assert_receive :closed
  end

  test "passes chunks through a Req-style into callback and stops when it halts" do
    parent = self()

    into = fn {:data, chunk}, {request, response} ->
      send(parent, {:chunk, chunk})

      if chunk == "stop",
        do: {:halt, {request, %{response | body: :response_too_large}}},
        else: {:cont, {request, %{response | body: response.body <> chunk}}}
    end

    stub_connection([
      [{:status, @ref, 200}, {:headers, @ref, []}, {:data, @ref, "first"}, {:data, @ref, "stop"}],
      [{:data, @ref, "never"}, {:done, @ref}]
    ])

    assert {:ok, %{status: 200, body: :response_too_large}} =
             JWKSClient.get("https://203.0.113.10/jwks", opts(into: into))

    assert_receive {:chunk, "first"}
    assert_receive {:chunk, "stop"}
    refute_receive {:chunk, "never"}
    assert_receive :closed
  end

  test "enforces the body limit even when the into callback keeps accumulating" do
    into = fn {:data, chunk}, {request, response} -> {:cont, {request, %{response | body: response.body <> chunk}}} end

    stub_connection([[{:status, @ref, 200}, {:headers, @ref, []}, {:data, @ref, String.duplicate("a", 65_537)}]])

    assert {:error, :response_too_large} = JWKSClient.get("https://203.0.113.10/jwks", opts(into: into))
    assert_receive :closed
  end

  test "returns transport errors and closes the connection" do
    stub_connection([[{:status, @ref, 200}, {:headers, @ref, []}], {:error, %Mint.TransportError{reason: :timeout}}])

    assert {:error, %Mint.TransportError{reason: :timeout}} = JWKSClient.get("https://203.0.113.10/jwks", opts())
    assert_receive :closed
  end

  test "rejects data that arrives before a final status" do
    stub_connection([[{:data, @ref, "{}"}, {:done, @ref}]])

    assert {:error, :unexpected_response} = JWKSClient.get("https://203.0.113.10/jwks", opts())
    assert_receive :closed
  end

  test "bounds the total receive time for servers that trickle bytes" do
    stub_connection(List.duplicate([], 1_000))

    stub(Mint.HTTP, :recv, fn @conn, 0, timeout ->
      send(self(), {:recv, timeout})
      Process.sleep(min(timeout, 20))
      {:ok, @conn, []}
    end)

    assert {:error, :timeout} = JWKSClient.get("https://203.0.113.10/jwks", opts(total_timeout: 100))
    assert_receive :closed
  end

  test "does not close a connection that was never opened" do
    stub_connection([])
    stub(Mint.HTTP, :connect, fn _, _, _, _ -> {:error, %Mint.TransportError{reason: :econnrefused}} end)
    reject(&Mint.HTTP.close/1)

    assert {:error, %Mint.TransportError{reason: :econnrefused}} = JWKSClient.get("https://203.0.113.10/jwks", opts())
  end

  test "closes the connection when the request can't be sent" do
    stub_connection([])
    stub(Mint.HTTP, :request, fn @conn, _, _, _, _ -> {:error, @conn, %Mint.TransportError{reason: :closed}} end)

    assert {:error, %Mint.TransportError{reason: :closed}} = JWKSClient.get("https://203.0.113.10/jwks", opts())
    assert_receive :closed
  end

  test "closes the connection when a callback raises" do
    stub_connection([[{:status, @ref, 200}, {:headers, @ref, []}, {:data, @ref, "{}"}]])

    assert_raise RuntimeError, fn ->
      JWKSClient.get("https://203.0.113.10/jwks", opts(into: fn _, _ -> raise "boom" end))
    end

    assert_receive :closed
  end

  test "only accepts HTTPS URLs without credentials" do
    reject(&Mint.HTTP.connect/4)

    for url <- ["http://203.0.113.10/jwks", "https://user:pass@203.0.113.10/jwks", "https:///jwks", "not a url", nil] do
      assert {:error, :invalid_url} = JWKSClient.get(url, opts())
    end
  end

  test "refuses hostnames so DNS can't be resolved again after pinning" do
    reject(&Mint.HTTP.connect/4)

    for url <- ["https://keys.example/jwks", "https://localhost/jwks", "https://0x7f.0.0.1/jwks"] do
      assert {:error, :unpinned_host} = JWKSClient.get(url, opts())
    end
  end

  test "never starts Req or Finch connection pools, whatever the hostname" do
    stub_connection(List.duplicate([{:status, @ref, 200}, {:headers, @ref, []}, {:done, @ref}], 10))
    %{active: pools_before} = DynamicSupervisor.count_children(Req.FinchSupervisor)

    for index <- 1..10 do
      connect_options = [
        hostname: "keys-#{index}.example",
        transport_opts: [server_name_indication: ~c"keys-#{index}.example"],
        timeout: 5_000
      ]

      assert {:ok, %{status: 200}} =
               JWKSClient.get("https://203.0.113.10/jwks", opts(connect_options: connect_options))
    end

    assert %{active: ^pools_before} = DynamicSupervisor.count_children(Req.FinchSupervisor)
  end
end
