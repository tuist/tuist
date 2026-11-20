defmodule LuftServer.Agents.RunnerTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias LuftServer.Agents.Kind
  alias LuftServer.Agents.Lease
  alias LuftServer.Agents.Runner
  alias LuftServer.Repo

  defmodule FakeKind do
    @moduledoc false
    @behaviour Kind

    @impl true
    def start(id, epoch) do
      {:ok, pid} = Agent.start(fn -> :busy end)
      Agent.update(__MODULE__, &Map.put(&1, id, %{pid: pid, epoch: epoch}))
      {:ok, pid}
    end

    @impl true
    def stop_if_idle(pid, reply_to, token) do
      Agent.cast(pid, fn state ->
        if state == :idle do
          send(reply_to, {Kind, :idle, self(), token})
          exit(:normal)
        end

        state
      end)
    end

    @impl true
    def drain(pid) do
      Agent.cast(pid, fn
        :stuck -> :stuck
        _state -> exit({:shutdown, :drain})
      end)
    end

    def session(id), do: Agent.get(__MODULE__, &Map.fetch!(&1, id))
  end

  setup do
    if !Process.whereis(LuftServer.PubSub),
      do: start_supervised!({Phoenix.PubSub, name: LuftServer.PubSub})

    owner = Sandbox.start_owner!(Repo, shared: true)
    on_exit(fn -> Sandbox.stop_owner(owner) end)

    start_supervised!(%{
      id: FakeKind,
      start: {Agent, :start_link, [fn -> %{} end, [name: FakeKind]]}
    })

    :ok
  end

  test "hosts work, stops idle sessions and spends only observed wants" do
    id = Ecto.UUID.generate()
    Lease.want(id, "fake")
    runner = start_runner()
    eventually(fn -> Runner.hosted(runner) == [id] end)
    Agent.update(FakeKind.session(id).pid, fn _ -> :idle end)
    send(runner, :renew)
    eventually(fn -> Runner.hosted(runner) == [] end)

    assert %{rows: [[false, nil]]} =
             Repo.query!("SELECT wanted, host FROM agent_sessions WHERE id=$1", [id])
  end

  test "shutdown drains and hands sessions off at a later epoch" do
    id = Ecto.UUID.generate()
    Lease.want(id, "fake")
    runner = start_runner()
    eventually(fn -> Runner.hosted(runner) == [id] end)
    old = FakeKind.session(id)
    GenServer.stop(runner)
    refute Process.alive?(old.pid)
    other = start_runner()
    eventually(fn -> Runner.hosted(other) == [id] end)
    assert FakeKind.session(id).epoch > old.epoch
  end

  test "shutdown releases even a session that misses the drain deadline" do
    id = Ecto.UUID.generate()
    Lease.want(id, "fake")
    runner = start_runner(drain_ms: 5)
    eventually(fn -> Runner.hosted(runner) == [id] end)
    old = FakeKind.session(id)
    Agent.update(old.pid, fn _ -> :stuck end)

    try do
      GenServer.stop(runner)
      assert Process.alive?(old.pid)
      assert [%{epoch: epoch}] = Lease.claim("successor", 1)
      assert epoch > old.epoch
    after
      Agent.stop(old.pid)
    end
  end

  test "lost lease drains without releasing the successor" do
    id = Ecto.UUID.generate()
    Lease.want(id, "fake")
    runner = start_runner()
    eventually(fn -> Runner.hosted(runner) == [id] end)
    old = FakeKind.session(id)

    Repo.query!(
      "UPDATE agent_sessions SET lease_expires_at=CURRENT_TIMESTAMP - interval '1 second' WHERE id=$1",
      [id]
    )

    assert [%{epoch: epoch}] = Lease.claim("successor", 1)
    send(runner, :renew)
    eventually(fn -> Runner.hosted(runner) == [] end)
    eventually(fn -> not Process.alive?(old.pid) end)

    assert %{rows: [["successor", ^epoch]]} =
             Repo.query!("SELECT host, epoch FROM agent_sessions WHERE id=$1", [id])
  end

  test "unavailable session backs off until a new want" do
    id = Ecto.UUID.generate()
    Lease.want(id, "fake")
    runner = start_runner(retry_ms: 60_000)
    eventually(fn -> Runner.hosted(runner) == [id] end)
    old = FakeKind.session(id)
    Agent.stop(old.pid, {:shutdown, :unavailable})
    eventually(fn -> Runner.hosted(runner) == [] end)
    assert Lease.claim("other", 1) == []
    Lease.want(id, "fake")
    Lease.wake(id)
    eventually(fn -> Runner.hosted(runner) == [id] end)
    assert FakeKind.session(id).epoch > old.epoch
  end

  test "count and memory limits bound admission" do
    for _ <- 1..3, do: Lease.want(Ecto.UUID.generate(), "fake")
    runner = start_runner(max_sessions: 2)
    eventually(fn -> length(Runner.hosted(runner)) == 2 end)
    other = start_runner(memory_limit_bytes: 100, memory: fn -> 80 end)
    send(other, :claim)
    assert Runner.hosted(other) == []
  end

  defp start_runner(opts \\ []) do
    opts =
      Keyword.merge([name: nil, host: Ecto.UUID.generate(), kinds: %{"fake" => FakeKind}], opts)

    start_supervised!(%{
      id: make_ref(),
      start: {Runner, :start_link, [opts]},
      restart: :temporary,
      shutdown: 30_000
    })
  end

  defp eventually(fun, tries \\ 100) do
    if fun.() do
      :ok
    else
      if tries == 0, do: flunk("condition never held")
      Process.sleep(10)
      eventually(fun, tries - 1)
    end
  end
end
