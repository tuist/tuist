# Isolated two-node discovery check; never connects to an existing cluster or database.
# ERL_FLAGS='+S 2:2' MIX_ENV=test elixir --name formation_root@127.0.0.1 \
#   --cookie formation_verification -S mix run --no-start --no-compile verification/cluster_formation.exs
Process.flag(:trap_exit, true)
{:ok, _} = Application.ensure_all_started(:libcluster)

wait = fn predicate ->
  Enum.reduce_while(1..100, nil, fn _, _ ->
    if predicate.(),
      do: {:halt, :ok},
      else:
        (
          Process.sleep(50)
          {:cont, nil}
        )
  end) || raise "Timed out waiting for owned cluster membership"
end

{:ok, peer, remote} =
  :peer.start_link(%{
    name: :formation_peer,
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
        ~c"19101",
        ~c"inet_dist_listen_max",
        ~c"19101",
        ~c"-pa"
      ] ++ :code.get_path()
  })

try do
  [] = Node.list()

  topologies = [
    verification: [
      strategy: Cluster.Strategy.Kubernetes.DNS,
      config: [
        service: "localhost",
        application_name: "formation_peer",
        polling_interval: 100,
        resolver: fn host -> :inet.gethostbyname(host, :inet) end
      ]
    ]
  ]

  {:ok, cluster} = Supervisor.start_link(Tuist.Application.RuntimeChildren.cluster(topologies), strategy: :one_for_one)

  try do
    wait.(fn -> remote in Node.list() end)
    :global.sync()
    {:ok, 19_101} = :erpc.call(remote, :application, :get_env, [:kernel, :inet_dist_listen_min])
    {:ok, 19_101} = :erpc.call(remote, :application, :get_env, [:kernel, :inet_dist_listen_max])
    cookie = Node.get_cookie()
    ^cookie = :erpc.call(remote, :erlang, :get_cookie, [])
    IO.puts("PASS: configured discovery joins two owned nodes with a shared cookie and fixed peer listener")
    :peer.stop(peer)
    wait.(fn -> remote not in Node.list() end)
    IO.puts("PASS: owned peer departure is observed")
  after
    Supervisor.stop(cluster)
  end
after
  if Process.alive?(peer), do: :peer.stop(peer)
end
