# Run only in an owned, loopback-bound named VM, without starting the server:
# ERL_FLAGS='+S 2:2 -kernel inet_dist_use_interface {127,0,0,1}' MIX_ENV=test \
#   elixir --name scale_$$@127.0.0.1 --cookie scale_verification \
#   -S mix run --no-start verification/cluster_scale_out.exs

helpers =
  Code.compile_string("""
  defmodule ClusterScaleOut.Owner do
    @moduledoc false

    def start(controller) do
      spawn(fn ->
        monitor = Process.monitor(controller)
        caches = [:display, :tuist, :license, :token_verification, :auth_subjects]
        children = Enum.map(caches, &%{id: &1, start: {Cachex, :start_link, [&1, []]}, type: :supervisor})
        children = children ++ [
          {Phoenix.PubSub, name: Tuist.PubSub},
          %{id: :flags, start: {FunWithFlags.Store.Cache, :start_link, []}},
          Tuist.KeyValueStore.Invalidator
        ]
        {:ok, supervisor} = Supervisor.start_link(children, strategy: :one_for_one)
        Phoenix.PubSub.subscribe(Tuist.PubSub, "scale_probe:barrier")
        send(controller, {:probe_ready, self()})
        loop(supervisor, monitor)
      end)
    end

    defp loop(supervisor, monitor) do
      receive do
        {:barrier, target, controller, ref} ->
          if node() == target, do: send(controller, {:barrier, ref})
          loop(supervisor, monitor)
        {:DOWN, ^monitor, :process, _, _} -> Supervisor.stop(supervisor)
        :stop -> Supervisor.stop(supervisor)
      end
    end
  end
  """)

defmodule ClusterScaleOut do
  @moduledoc false

  alias FunWithFlags.Flag
  alias FunWithFlags.Store.Cache, as: FlagCache
  alias Tuist.KeyValueStore
  alias Tuist.KeyValueStore.Invalidator

  @protected [:tuist, :license, :token_verification, :auth_subjects]

  def run(helpers) do
    if !(Node.alive?() and Node.list(:connected) == [] and is_nil(Process.whereis(Tuist.Supervisor))) do
      raise "use an isolated named VM without a running server"
    end

    if Application.get_env(:kernel, :inet_dist_use_interface) != {127, 0, 0, 1} do
      raise "bind distribution to loopback before starting the VM"
    end

    {:ok, _} = Application.ensure_all_started(:cachex)
    {:ok, _} = Application.ensure_all_started(:phoenix_pubsub)
    local_owner = ClusterScaleOut.Owner.start(self())

    try do
      ready(local_owner)
      verify_peer(helpers)
    after
      stop_owner(local_owner)
    end
  end

  defp verify_peer(helpers) do
    suffix = System.pid() <> "_" <> Integer.to_string(System.unique_integer([:positive]))

    {:ok, peer, remote} =
      :peer.start_link(%{
        name: String.to_atom("scale_peer_" <> suffix),
        host: ~c"127.0.0.1",
        longnames: true,
        connection: :standard_io,
        args:
          [
            ~c"+S",
            ~c"2:2",
            ~c"-setcookie",
            Atom.to_charlist(Node.get_cookie()),
            ~c"-kernel",
            ~c"inet_dist_use_interface",
            ~c"{127,0,0,1}",
            ~c"-pa"
          ] ++ :code.get_path()
      })

    try do
      for app <- [:elixir, :cachex, :phoenix_pubsub] do
        {:ok, _} = :peer.call(peer, Application, :ensure_all_started, [app])
      end

      for {module, binary} <- helpers do
        {:module, ^module} = :peer.call(peer, :code, :load_binary, [module, ~c"scale_probe", binary])
      end

      true = Node.connect(remote)
      owner = :peer.call(peer, ClusterScaleOut.Owner, :start, [self()])
      ready(owner)
      await(fn -> pubsub_ready?(remote) end, "PubSub forwarding did not become ready")
      verify_invalidation(remote)

      :ok = Cachex.put(:display, "missed-invalidation", :stale)
      flag = %Flag{name: :scale_out_verification}
      {:ok, ^flag} = FlagCache.put(flag)
      {:ok, ^flag} = FlagCache.get(flag.name)
      :ok = :peer.stop(peer)
      await(fn -> remote not in Node.list(:connected) end, "owned peer did not depart")
      await(fn -> Cachex.get(:display, "missed-invalidation") == nil end, "departure did not evict display entries")
      await(fn -> FlagCache.get(flag.name) == {:miss, :not_found, nil} end, "departure did not flush flag cache")
      protected_warm(node())
      IO.puts("PASS: actual peer departure evicts display/flag entries and preserves protected cache markers")
    after
      if Process.alive?(peer), do: :peer.stop(peer)
    end
  end

  defp verify_invalidation(remote) do
    for target <- [node(), remote] do
      for cache <- [:display | @protected] do
        :ok = :erpc.call(target, Cachex, :put, [cache, "balance", :warm])
      end

      {:ok, true} = :erpc.call(target, KeyValueStore, :put, ["unrelated", :warm, [cache: :display]])
    end

    :ok = KeyValueStore.invalidate("balance", cache: :display)
    {:ok, true} = KeyValueStore.put("balance", :replacement, cache: :display)

    await(
      fn -> :erpc.call(remote, KeyValueStore, :get, ["balance", [cache: :display]]) == nil end,
      "remote invalidation missing"
    )

    :sys.get_state(Invalidator)
    :replacement = KeyValueStore.get("balance", cache: :display)

    for target <- [node(), remote] do
      :warm = :erpc.call(target, KeyValueStore, :get, ["unrelated", [cache: :display]])
      protected_warm(target)
    end

    IO.puts(
      "PASS: cross-node display invalidation preserves unrelated entries, local replacement and protected cache markers"
    )
  end

  defp protected_warm(target) do
    for cache <- @protected, do: :warm = :erpc.call(target, Cachex, :get, [cache, "balance"])
  end

  defp pubsub_ready?(remote) do
    ref = make_ref()
    Phoenix.PubSub.broadcast(Tuist.PubSub, "scale_probe:barrier", {:barrier, remote, self(), ref})

    receive do
      {:barrier, ^ref} -> true
    after
      50 -> false
    end
  end

  defp ready(owner) do
    ref = Process.monitor(owner)

    receive do
      {:probe_ready, ^owner} -> Process.demonitor(ref, [:flush])
      {:DOWN, ^ref, :process, ^owner, reason} -> raise "owned cache supervisor failed: #{inspect(reason)}"
    after
      5_000 -> raise "owned cache supervisor did not start"
    end
  end

  defp stop_owner(owner) do
    ref = Process.monitor(owner)
    send(owner, :stop)

    receive do
      {:DOWN, ^ref, :process, ^owner, _} -> :ok
    after
      5_000 -> raise "owned cache supervisor did not stop"
    end
  end

  defp await(check, message, remaining \\ 100)
  defp await(_check, message, 0), do: raise(message)

  defp await(check, message, remaining) do
    if check.() do
      :ok
    else
      Process.sleep(50)
      await(check, message, remaining - 1)
    end
  end
end

ClusterScaleOut.run(helpers)
