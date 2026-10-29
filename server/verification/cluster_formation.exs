# Run in an owned named VM, never attached to an existing cluster:
# ERL_FLAGS='+S 2:2' MIX_ENV=test elixir --name formation_$$@127.0.0.1 \
#   --cookie formation_verification -S mix run --no-start verification/cluster_formation.exs

defmodule ClusterFormation.Observer do
  @moduledoc false
  def start do
    parent = self()

    pid =
      spawn(fn ->
        :net_kernel.monitor_nodes(true)
        send(parent, {:monitor_ready, self()})
        loop([])
      end)

    receive do
      {:monitor_ready, ^pid} -> pid
    after
      5_000 -> raise "node monitor did not start"
    end
  end

  def events(pid) do
    ref = make_ref()
    send(pid, {:events, self(), ref})

    receive do
      {^ref, events} -> events
    after
      5_000 -> raise "node monitor did not reply"
    end
  end

  defp loop(events) do
    receive do
      {:nodedown, node} ->
        loop([node | events])

      {:events, caller, ref} ->
        send(caller, {ref, events})
        loop([])

      _ ->
        loop(events)
    end
  end
end

defmodule ClusterFormation do
  @moduledoc false
  alias Tuist.Application.RuntimeChildren

  def run do
    if not Node.alive?() or Node.list() != [], do: raise("use an isolated, named verification VM")
    Application.ensure_all_started(:libcluster)
    suffix = System.pid() <> "_" <> Integer.to_string(System.unique_integer([:positive]))
    cookie = Atom.to_charlist(Node.get_cookie())
    args = [~c"+S", ~c"2:2", ~c"-setcookie", cookie, ~c"-pa"] ++ :code.get_path()

    {:ok, peer, peer_node} =
      :peer.start_link(%{
        name: String.to_atom("formation_peer_" <> suffix),
        host: ~c"127.0.0.1",
        connection: :standard_io,
        args: args
      })

    {:ok, other, other_node} =
      :peer.start_link(%{
        name: String.to_atom("formation_other_" <> suffix),
        host: ~c"127.0.0.1",
        connection: :standard_io,
        args: args
      })

    wrong_args = [~c"+S", ~c"2:2", ~c"-setcookie", ~c"wrong_formation_cookie", ~c"-pa"] ++ :code.get_path()

    {:ok, wrong, wrong_node} =
      :peer.start_link(%{
        name: String.to_atom("formation_wrong_" <> suffix),
        host: ~c"127.0.0.1",
        connection: :standard_io,
        args: wrong_args
      })

    try do
      verify(peer_node, other_node, wrong_node)
    after
      for owned <- [peer, other, wrong] do
        if Process.alive?(owned), do: :peer.stop(owned)
      end
    end
  end

  defp verify(peer, other, wrong) do
    {:ok, mode} = Agent.start_link(fn -> :healthy end)

    topologies =
      for {name, node} <- [first: peer, second: other] do
        prefix = node |> Atom.to_string() |> String.split("@") |> hd()

        {name,
         strategy: Cluster.Strategy.Kubernetes.DNS,
         config: [
           service: "localhost",
           application_name: prefix,
           polling_interval: 100,
           resolver: fn _ ->
             case Agent.get(mode, & &1) do
               :error -> {:error, :timeout}
               :omit_first when name == :first -> {:ok, {:hostent, ~c"localhost", [], :inet, 4, []}}
               _ -> {:ok, {:hostent, ~c"localhost", [], :inet, 4, [{127, 0, 0, 1}]}}
             end
           end
         ]}
      end

    {:ok, supervisor} = Supervisor.start_link(RuntimeChildren.cluster(topologies), strategy: :one_for_one)

    try do
      await(fn -> Enum.all?([peer, other], &(&1 in Node.list())) end, "DNS discovery did not join owned peers")
      true = :erpc.call(peer, Node, :connect, [other])
      await(fn -> length(:erpc.call(peer, Node, :list, [])) == 2 end, "three-node mesh did not converge")
      observer = ClusterFormation.Observer.start()

      for fault <- [:error, :omit_first] do
        Agent.update(mode, fn _ -> fault end)
        Process.sleep(400)
        [] = ClusterFormation.Observer.events(observer)
        true = Enum.all?([peer, other], &(&1 in Node.list()))
        Agent.update(mode, fn _ -> :healthy end)
        Process.sleep(200)
        [] = ClusterFormation.Observer.events(observer)
      end

      IO.puts("PASS: configured DNS discovery, failed polls and partial answers retain the owned three-node mesh")

      false = Node.connect(wrong)
      false = wrong in Node.list()
      IO.puts("PASS: a wrong-cookie peer cannot join")

      :ok = :erpc.call(peer, :init, :stop, [])
      await(fn -> peer not in Node.list() end, "owned peer departure was not observed")
      true = other in Node.list()
      IO.puts("PASS: actual peer departure is observed while the other connection remains")
    after
      Supervisor.stop(supervisor)
      Agent.stop(mode)
    end
  end

  defp await(check, message, attempts \\ 200)
  defp await(_check, message, 0), do: raise(message)

  defp await(check, message, attempts) do
    if check.() do
      :ok
    else
      Process.sleep(50)
      await(check, message, attempts - 1)
    end
  end
end

ClusterFormation.run()
