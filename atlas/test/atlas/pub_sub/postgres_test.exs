defmodule Atlas.PubSub.PostgresTest do
  use ExUnit.Case, async: true
  use Mimic

  import ExUnit.CaptureLog

  alias Atlas.PubSub.Postgres
  alias Atlas.PubSub.Postgres.Listener
  alias Atlas.Repo
  alias Ecto.Adapters.SQL.Sandbox
  alias Phoenix.PubSub
  alias Postgrex.SimpleConnection

  setup do
    suffix = System.unique_integer([:positive])
    channel = "atlas_pubsub_test_#{suffix}"
    names = for replica <- 1..2, do: :"atlas_pubsub_#{suffix}_#{replica}"

    for name <- names do
      start_supervised!(Supervisor.child_spec({PubSub, name: name, adapter: Postgres, channel: channel}, id: name))
      # Synchronize with initial LISTEN without making publishers depend on it.
      assert PubSub.node_name(name) == SimpleConnection.call(listener(name), :instance_id)
    end

    {:ok, replicas: names}
  end

  test "ignores malformed payloads and unexpected notification channels", %{replicas: [first, _second]} do
    state = %{channel: "expected", pubsub: first, instance_id: "local"}
    assert :ok = Postgres.notify("other", "ignored", state)
    assert :ok = Postgres.notify("expected", "not base64", state)
    assert :ok = Postgres.notify("expected", Base.encode64("not an Erlang term"), state)

    PubSub.subscribe(first, "topic")

    for envelope <- [
          {1, "remote", nil, 123, :invalid, PubSub},
          {1, "remote", nil, "topic", :invalid, :not_a_dispatcher},
          {1, "remote", :invalid_target, "topic", :invalid, PubSub},
          {2, "remote", nil, "topic", :invalid, PubSub},
          {"remote", nil, "topic", :invalid, PubSub}
        ] do
      payload = envelope |> :erlang.term_to_binary() |> Base.encode64()
      assert :ok = Postgres.notify("expected", payload, state)
    end

    refute_receive :invalid
  end

  test "a suspended listener cannot block node identity or publication", %{replicas: [first, second]} do
    PubSub.subscribe(first, "topic")
    PubSub.subscribe(second, "topic")
    identity = PubSub.node_name(first)
    pid = listener(first)
    :ok = :sys.suspend(pid)

    try do
      task =
        Task.async(fn ->
          assert PubSub.node_name(first) == identity
          Sandbox.unboxed_run(Repo, fn -> PubSub.broadcast(first, "topic", :while_suspended) end)
        end)

      assert :ok = Task.await(task, 1_000)
      assert_receive :while_suspended
      assert_receive :while_suspended
    after
      :sys.resume(pid)
    end

    assert SimpleConnection.call(pid, :instance_id) == identity
    refute_receive :while_suspended
  end

  test "a stopped listener keeps its identity and does not block local or remote publication", %{
    replicas: [first, second]
  } do
    PubSub.subscribe(first, "topic")
    PubSub.subscribe(second, "topic")
    adapter = Module.concat(first, "Adapter")
    identity = PubSub.node_name(first)
    assert :ok = Supervisor.terminate_child(adapter, Listener)

    assert PubSub.node_name(first) == identity
    assert :ok = Sandbox.unboxed_run(Repo, fn -> PubSub.broadcast(first, "topic", :while_stopped) end)
    assert_receive :while_stopped
    assert_receive :while_stopped

    assert {:ok, pid} = Supervisor.restart_child(adapter, Listener)
    assert SimpleConnection.call(pid, :instance_id) == identity
    refute_receive :while_stopped
  end

  test "publication errors preserve local delivery and do not log notification data", %{
    replicas: [first, second]
  } do
    PubSub.subscribe(first, "topic")
    PubSub.subscribe(second, "topic")
    expect(Repo, :query, fn _, _ -> {:error, %{secret: "synthetic_secret"}} end)

    log = capture_log(fn -> assert :ok = PubSub.broadcast(first, "topic", :local_only) end)
    assert log =~ "remote publication failed"
    refute log =~ "synthetic_secret"
    assert_receive :local_only
    refute_receive :local_only
  end

  test "metadata missing during adapter startup or shutdown does not crash publishers" do
    adapter = :"pubsub_metadata_race_#{System.unique_integer([:positive])}"
    assert Postgres.node_name(adapter) == :undefined

    capture_log(fn ->
      assert :ok = Postgres.broadcast(adapter, "topic", :unavailable, PubSub)
      :ets.new(adapter, [:named_table, :protected])
      assert :ok = Postgres.broadcast(adapter, "topic", :starting, PubSub)
      assert Postgres.node_name(adapter) == :undefined
    end)
  end

  test "publication exceptions preserve local delivery", %{replicas: [first, _second]} do
    PubSub.subscribe(first, "topic")
    expect(Repo, :query, fn _, _ -> raise DBConnection.ConnectionError, message: "synthetic_secret" end)

    log = capture_log(fn -> assert :ok = PubSub.broadcast(first, "topic", :local_after_exception) end)
    refute log =~ "synthetic_secret"
    assert_receive :local_after_exception
  end

  test "a terminated PostgreSQL session reconnects and reissues LISTEN", %{replicas: [first, second]} do
    PubSub.subscribe(second, "topic")
    pid = listener(second)
    {_state, %{protocol: %{connection_id: backend_id}}} = :sys.get_state(pid)
    identity = PubSub.node_name(second)

    capture_log(fn ->
      assert %{rows: [[true]]} =
               Sandbox.unboxed_run(Repo, fn -> Repo.query!("SELECT pg_terminate_backend($1)", [backend_id]) end)

      await_reconnect(pid, backend_id, System.monotonic_time(:millisecond) + 10_000)
    end)

    assert PubSub.node_name(second) == identity
    assert :ok = Sandbox.unboxed_run(Repo, fn -> PubSub.broadcast(first, "topic", :after_reconnect) end)
    assert_receive :after_reconnect
    refute_receive :after_reconnect
  end

  test "delivers cross-replica notifications once without Distributed Erlang", %{replicas: [first, second]} do
    topic = "topic"
    PubSub.subscribe(first, topic)
    PubSub.subscribe(second, topic)

    assert :ok = Sandbox.unboxed_run(Repo, fn -> PubSub.broadcast(first, topic, {:changed, 123}) end)
    assert_receive {:changed, 123}
    assert_receive {:changed, 123}
    refute_receive {:changed, 123}
  end

  test "direct broadcasts route by replica identity", %{replicas: [first, second]} do
    PubSub.subscribe(first, "topic")
    PubSub.subscribe(second, "topic")
    target = PubSub.node_name(second)

    assert :ok = Sandbox.unboxed_run(Repo, fn -> PubSub.direct_broadcast(target, first, "topic", :direct) end)
    assert_receive :direct
    refute_receive :direct
  end

  test "oversized notifications fail explicitly rather than silently dropping remote delivery", %{
    replicas: [first, second]
  } do
    PubSub.subscribe(first, "topic")
    PubSub.subscribe(second, "topic")
    message = String.duplicate("x", 8_000)

    assert {:error, :notification_too_large} = PubSub.broadcast(first, "topic", message)
    refute_receive ^message
  end

  defp listener(pubsub) do
    [{Listener, pid, :worker, _modules}] = Supervisor.which_children(Module.concat(pubsub, "Adapter"))
    pid
  end

  defp await_reconnect(pid, old_backend, deadline) do
    {_state, connection} = :sys.get_state(pid)

    case connection.protocol do
      %{connection_id: backend} when backend != old_backend ->
        assert is_binary(SimpleConnection.call(pid, :instance_id))

      _ ->
        assert System.monotonic_time(:millisecond) < deadline, "LISTEN did not reconnect"
        await_reconnect(pid, old_backend, deadline)
    end
  end

  test "notifications from rolled-back writes never reach the other replica", %{replicas: [first, second]} do
    PubSub.subscribe(second, "topic")

    assert {:error, :rollback} =
             Sandbox.unboxed_run(Repo, fn ->
               Repo.transaction(fn ->
                 assert :ok = PubSub.broadcast(first, "topic", :rolled_back)
                 Repo.rollback(:rollback)
               end)
             end)

    refute_receive :rolled_back
  end
end
