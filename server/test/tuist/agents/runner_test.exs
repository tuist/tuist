defmodule Tuist.Agents.RunnerTest do
  # The runner is its own process, so it shares the test's sandbox connection.
  use TuistTestSupport.Cases.DataCase, async: false
  use Mimic

  alias Tuist.Agents.Kind
  alias Tuist.Agents.Lease
  alias Tuist.Agents.Runner

  defmodule FakeKind do
    @moduledoc false
    @behaviour Kind

    def state, do: __MODULE__.State

    @impl true
    def start(id, epoch) do
      {:ok, pid} = Agent.start(fn -> :busy end)
      Agent.update(state(), &Map.put(&1, id, %{pid: pid, epoch: epoch, stopped: nil}))
      {:ok, pid}
    end

    @impl true
    def stop_if_idle(pid, reply_to, token) do
      if Agent.get(pid, & &1) == :idle do
        mark(pid, :idle)
        send(reply_to, {Kind, :idle, pid, token})
        Agent.stop(pid)
      end

      :ok
    end

    @impl true
    def drain(pid) do
      mark(pid, :drain)
      Agent.stop(pid, {:shutdown, :drain})
    end

    defp mark(pid, how) do
      Agent.update(state(), fn sessions ->
        Map.new(sessions, fn {id, s} -> {id, if(s.pid == pid, do: %{s | stopped: how}, else: s)} end)
      end)
    end

    def session(id), do: Agent.get(state(), & &1[id])
  end

  setup :set_mimic_global

  setup do
    start_supervised!(%{id: FakeKind.State, start: {Agent, :start_link, [fn -> %{} end, [name: FakeKind.State]]}})
    :ok
  end

  defp start_runner(opts \\ []) do
    opts = Keyword.merge([name: nil, host: "host-#{System.unique_integer()}", kinds: %{"fake" => FakeKind}], opts)
    # Temporary, so a runner a test stops stays stopped.
    pid =
      start_supervised!(%{
        id: make_ref(),
        start: {GenServer, :start_link, [Runner, opts]},
        restart: :temporary,
        shutdown: 5_000
      })

    {pid, opts[:host]}
  end

  defp row(id) do
    Repo.one(
      from(s in "agent_sessions",
        where: s.id == ^id,
        select: %{wanted: s.wanted, host: s.host, epoch: s.epoch}
      )
    )
  end

  defp eventually(fun, tries \\ 100) do
    if fun.() do
      :ok
    else
      if tries == 0, do: flunk("condition never held")
      Process.sleep(30)
      eventually(fun, tries - 1)
    end
  end

  test "hosts a wanted session, and releases it once it is idle" do
    id = "s-" <> Ecto.UUID.generate()
    Lease.want(id, "fake")
    {runner, host} = start_runner()

    eventually(fn -> Runner.hosted(runner) == [id] end)
    assert %{wanted: true, host: ^host} = row(id)

    Agent.update(FakeKind.session(id).pid, fn _ -> :idle end)
    send(runner, :renew)

    eventually(fn -> Runner.hosted(runner) == [] end)
    assert FakeKind.session(id).stopped == :idle
    assert %{wanted: false, host: nil} = row(id)
  end

  test "a want stored after the idle check keeps the session wanted; none releases it" do
    id = "s-" <> Ecto.UUID.generate()
    Lease.want(id, "fake")
    [%{epoch: epoch}] = Enum.filter(Lease.claim("host-a", 100), &(&1.id == id))
    %{{^id, ^epoch} => seen} = Lease.renew("host-a", [{id, epoch}])

    # A message's want lands between the renewal's read and the release, in
    # the same instant as far as any clock could tell.
    Lease.want(id, "fake")
    :ok = Lease.release(id, epoch, wanted: false, seen: seen)
    assert %{wanted: true, host: nil} = row(id)

    [%{epoch: epoch}] = Enum.filter(Lease.claim("host-a", 100), &(&1.id == id))
    %{{^id, ^epoch} => seen} = Lease.renew("host-a", [{id, epoch}])
    :ok = Lease.release(id, epoch, wanted: false, seen: seen)
    assert %{wanted: false, host: nil} = row(id)
  end

  test "renewal does not wait on a session that never answers" do
    id = "s-" <> Ecto.UUID.generate()
    Lease.want(id, "fake")
    {runner, host} = start_runner()
    eventually(fn -> Runner.hosted(runner) == [id] end)
    %{epoch: epoch} = row(id)

    # A busy session ignores the idle request; renewal still answers at once.
    send(runner, :renew)
    assert Runner.hosted(runner) == [id]
    assert %{host: ^host, epoch: ^epoch} = row(id)
  end

  # The runner is a permanent child of the application: a database failover
  # must not crash it, and the sessions it hosts keep running.
  test "a renewal that fails on the database leaves the runner and its sessions running" do
    id = "s-" <> Ecto.UUID.generate()
    Lease.want(id, "fake")
    {runner, host} = start_runner()
    eventually(fn -> Runner.hosted(runner) == [id] end)

    stub(Lease, :renew, fn _host, _leases -> raise DBConnection.ConnectionError, "connection lost" end)
    ref = Process.monitor(runner)
    send(runner, :renew)
    assert Runner.hosted(runner) == [id]
    refute_received {:DOWN, ^ref, :process, ^runner, _reason}

    stub(Lease, :renew, &Mimic.call_original(Lease, :renew, [&1, &2]))
    send(runner, :renew)
    assert Runner.hosted(runner) == [id]
    assert %{host: ^host} = row(id)
  end

  test "honours the session cap" do
    ids = for _ <- 1..3, do: "s-" <> Ecto.UUID.generate()
    Enum.each(ids, &Lease.want(&1, "fake"))
    {runner, _host} = start_runner(max_sessions: 2)

    eventually(fn -> length(Runner.hosted(runner)) == 2 end)
    Process.sleep(100)
    assert length(Runner.hosted(runner)) == 2
  end

  test "claims nothing above its memory threshold" do
    id = "s-" <> Ecto.UUID.generate()
    Lease.want(id, "fake")
    {runner, _host} = start_runner(memory_limit_bytes: 100, memory: fn -> 80 end)

    Process.sleep(100)
    assert Runner.hosted(runner) == []
  end

  test "a session whose process ends is handed back, still wanted, to the next host" do
    id = "s-" <> Ecto.UUID.generate()
    Lease.want(id, "fake")
    {runner, _host} = start_runner()
    eventually(fn -> Runner.hosted(runner) == [id] end)
    %{epoch: first} = row(id)

    Agent.stop(FakeKind.session(id).pid, {:shutdown, :stale})
    # The same runner may claim it back; what matters is a new epoch.
    eventually(fn -> row(id).epoch > first end)
    assert row(id).wanted
  end

  # A session that could not reach its store, or whose process crashed, is
  # not claimed again at the pace of the poll, but a new want, such as a
  # message, makes it claimable.
  for {name, stop} <- [unavailable: {:stop, {:shutdown, :unavailable}}, crashed: {:exit, :kill}] do
    test "a session that ended #{name} is claimable again only after a delay" do
      id = "s-" <> Ecto.UUID.generate()
      Lease.want(id, "fake")
      {runner, _host} = start_runner(retry_ms: 60_000)
      eventually(fn -> Runner.hosted(runner) == [id] end)

      pid = FakeKind.session(id).pid

      case unquote(Macro.escape(stop)) do
        {:stop, reason} -> Agent.stop(pid, reason)
        {:exit, reason} -> Process.exit(pid, reason)
      end

      eventually(fn -> Runner.hosted(runner) == [] and row(id).host == nil end)

      assert row(id).wanted
      refute Enum.any?(Lease.claim("other-host", 100), &(&1.id == id))

      Lease.want(id, "fake")
      assert Enum.any?(Lease.claim("other-host", 100), &(&1.id == id))
    end
  end

  # As after a database outage longer than the lease: the poll claims the
  # session back before a renewal noticed it lapsed.
  test "claiming back a session it still hosts drains the old host first" do
    id = "s-" <> Ecto.UUID.generate()
    Lease.want(id, "fake")
    {runner, _host} = start_runner()
    eventually(fn -> Runner.hosted(runner) == [id] end)
    old = FakeKind.session(id)

    Repo.update_all(from(s in "agent_sessions", where: s.id == ^id),
      set: [lease_expires_at: DateTime.add(DateTime.utc_now(), -1)]
    )

    send(runner, :claim)
    eventually(fn -> FakeKind.session(id).epoch > old.epoch end)

    assert Runner.hosted(runner) == [id]
    refute Process.alive?(old.pid)
    assert Process.alive?(FakeKind.session(id).pid)
  end

  test "stopping the node drains its sessions and hands them to another host" do
    id = "s-" <> Ecto.UUID.generate()
    Lease.want(id, "fake")
    {runner, _host} = start_runner()
    eventually(fn -> Runner.hosted(runner) == [id] end)
    %{epoch: first} = row(id)
    pid = FakeKind.session(id).pid

    GenServer.stop(runner)
    assert FakeKind.session(id).stopped == :drain
    refute Process.alive?(pid)
    assert %{wanted: true, host: nil} = row(id)

    {other, host} = start_runner()
    eventually(fn -> Runner.hosted(other) == [id] end)
    assert %{host: ^host, epoch: epoch} = row(id)
    assert epoch > first
  end

  test "a session whose lease another host took is stopped without releasing it" do
    id = "s-" <> Ecto.UUID.generate()
    Lease.want(id, "fake")
    {runner, _host} = start_runner()
    eventually(fn -> Runner.hosted(runner) == [id] end)

    # Its lease lapsed, as during a long pause, and another host claimed it.
    Repo.update_all(from(s in "agent_sessions", where: s.id == ^id),
      set: [lease_expires_at: DateTime.add(DateTime.utc_now(), -1, :second)]
    )

    [%{epoch: taken}] = Enum.filter(Lease.claim("elsewhere", 10), &(&1.id == id))
    send(runner, :renew)

    eventually(fn -> Runner.hosted(runner) == [] end)
    assert FakeKind.session(id).stopped == :drain
    assert %{host: "elsewhere", epoch: ^taken} = row(id)
  end
end
