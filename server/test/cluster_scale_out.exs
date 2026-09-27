alias Tuist.KeyValueStore.Invalidator

# Run in an isolated named VM, without starting the server or its databases:
# MIX_ENV=test elixir --name scale_root@127.0.0.1 --cookie scale_verification -S mix run --no-start test/cluster_scale_out.exs
Process.flag(:trap_exit, true)

for app <- [:phoenix_pubsub, :cachex, :libcluster], do: Application.ensure_all_started(app)

helpers =
  Code.compile_string("""
  defmodule TuistScaleProbe do
    def start do
      spawn(__MODULE__, :boot, [])
    end

    def boot do
      {:ok, _} = Supervisor.start_link([
        {Cachex, [:tuist, []]},
        {Phoenix.PubSub, name: Tuist.PubSub},
        Tuist.KeyValueStore.Invalidator
      ], strategy: :one_for_one)
      receive do :stop -> :ok end
    end

    def try_lock(key, nodes) do
      id = {{Tuist.OpenGraphImages, key}, self()}
      acquired = :global.set_lock(id, nodes, 0)
      if acquired, do: :global.del_lock(id, nodes)
      acquired
    end

    def request do
      body = %{\"jsonrpc\" => \"2.0\", \"id\" => 1, \"method\" => \"tools/list\", \"params\" => %{
        \"_meta\" => %{\"io.modelcontextprotocol/protocolVersion\" => \"2026-07-28\", \"io.modelcontextprotocol/clientCapabilities\" => %{}}
      }}
      conn = Plug.Test.conn(:post, \"/mcp\")
        |> Map.put(:body_params, body)
        |> Plug.Conn.put_req_header(\"mcp-protocol-version\", \"2026-07-28\")
        |> Plug.Conn.put_req_header(\"mcp-method\", \"tools/list\")
        |> Plug.Conn.put_req_header(\"mcp-session-id\", \"stale-session-from-a-previous-instance\")
        |> Tuist.MCP.Transport.StreamableHTTP.call(server: Tuist.MCP.Server)
      {conn.status, Plug.Conn.get_resp_header(conn, \"mcp-session-id\"), JSON.decode!(conn.resp_body)[\"result\"][\"tools\"]}
    end
  end
  """)

wait = fn predicate ->
  Enum.reduce_while(1..100, nil, fn _, _ ->
    if predicate.(),
      do: {:halt, :ok},
      else:
        (
          Process.sleep(50)
          {:cont, nil}
        )
  end) || raise "Timed out waiting for cluster state"
end

{:ok, peer, remote} =
  :peer.start_link(%{
    name: :scale_peer,
    host: ~c"127.0.0.1",
    longnames: true,
    connection: :standard_io,
    args:
      [
        ~c"+S",
        ~c"2",
        ~c"-setcookie",
        Atom.to_charlist(Node.get_cookie()),
        ~c"-kernel",
        ~c"inet_dist_listen_min",
        ~c"19100",
        ~c"inet_dist_listen_max",
        ~c"19100",
        ~c"-pa"
      ] ++ :code.get_path()
  })

try do
  for app <- [:elixir, :plug, :phoenix_pubsub, :cachex], do: :peer.call(peer, Application, :ensure_all_started, [app])

  for {app, key, value} <- [{:plug, :validate_header_keys_during_test, true}, {:tuist, :environment, :test}],
      do: :peer.call(peer, Application, :put_env, [app, key, value])

  for {module, binary} <- helpers, do: :peer.call(peer, :code, :load_binary, [module, ~c"scale_probe", binary])

  [] = Node.list()

  topology = [
    verification: [
      strategy: Cluster.Strategy.Kubernetes.DNS,
      config: [
        service: "localhost",
        application_name: "scale_peer",
        polling_interval: 100,
        resolver: fn host -> :inet.gethostbyname(host, :inet) end
      ]
    ]
  ]

  {:ok, cluster} = Supervisor.start_link(Tuist.Application.RuntimeChildren.cluster(topology), strategy: :one_for_one)
  wait.(fn -> remote in Node.list() end)
  :global.sync()
  IO.puts("PASS: configured address discovery connected the Erlang nodes")
  {:ok, 19_100} = :erpc.call(remote, :application, :get_env, [:kernel, :inet_dist_listen_min])
  {:ok, 19_100} = :erpc.call(remote, :application, :get_env, [:kernel, :inet_dist_listen_max])

  local_owner = TuistScaleProbe.start()
  remote_owner = :erpc.call(remote, TuistScaleProbe, :start, [])

  wait.(fn ->
    Process.whereis(Invalidator) != nil and
      :erpc.call(remote, Process, :whereis, [Invalidator]) != nil
  end)

  :ok = Cachex.put(:tuist, "balance", :stale)
  :ok = :erpc.call(remote, Cachex, :put, [:tuist, "balance", :stale])
  :ok = Tuist.KeyValueStore.invalidate("balance")
  wait.(fn -> :erpc.call(remote, Cachex, :get, [:tuist, "balance"]) == nil end)
  IO.puts("PASS: publish/subscribe invalidated the remote cached balance")

  {200, [], local_tools} = TuistScaleProbe.request()
  {200, [], remote_tools} = :erpc.call(remote, TuistScaleProbe, :request, [])
  true = Enum.sort_by(local_tools, & &1["name"]) == Enum.sort_by(remote_tools, & &1["name"])
  IO.puts("PASS: modern tool discovery works on either node without initialization or sessions")

  id = {{Tuist.OpenGraphImages, "same"}, self()}
  true = :global.set_lock(id, [node(), remote], 0)
  false = :erpc.call(remote, TuistScaleProbe, :try_lock, ["same", [node(), remote]])
  true = :erpc.call(remote, TuistScaleProbe, :try_lock, ["different", [node(), remote]])
  :global.del_lock(id, [node(), remote])
  IO.puts("PASS: same-image locks exclude concurrent callers; different images proceed")

  :ok = Cachex.put(:tuist, "missed-invalidation", :stale)
  Supervisor.stop(cluster)
  :peer.stop(peer)
  wait.(fn -> Node.list() == [] and Cachex.get(:tuist, "missed-invalidation") == nil end)
  IO.puts("PASS: node departure clears local cache entries that may have missed invalidations")
  send(local_owner, :stop)
  _ = remote_owner
  IO.puts("All two-node scale-out checks passed")
after
  if Process.alive?(peer), do: :peer.stop(peer)
end
