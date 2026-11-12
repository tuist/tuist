defmodule Pulse.ObjectStoreAsyncTest do
  use Pulse.Test.Case, async: true

  alias Pulse.ObjectStore
  alias Pulse.Test.CompactionStore

  setup do
    store =
      start_supervised!(
        {Agent,
         fn ->
           %{
             objects: %{},
             reads: [],
             version: 0,
             hook: nil,
             faults: %{},
             barriers: %{},
             lists: 0,
             deletes: [],
             requests: []
           }
         end}
      )

    server = start_supervised!({Bandit, plug: {CompactionStore, agent: store}, ip: {127, 0, 0, 1}, port: 0})
    {:ok, {_, port}} = ThousandIsland.listener_info(server)

    config = %{
      bucket: "pulse",
      endpoint: "http://127.0.0.1:#{port}",
      region: "us-east-1",
      access_key_id: "test-#{System.unique_integer([:positive])}",
      secret_access_key: "test",
      allow_http: true
    }

    {:ok, config: config, store: store, key: "async-#{System.unique_integer([:positive])}.bin"}
  end

  test "requests in flight hold no dirty scheduler", ctx do
    assert {:ok, _etag} = ObjectStore.put(ctx.config, ctx.key, "body")
    owner = self()
    Agent.update(ctx.store, &put_in(&1.barriers[{"GET", ctx.key}], owner))

    # Far more stalled requests than dirty I/O schedulers: every one must reach
    # the provider at once, and dirty I/O work must still run meanwhile.
    count = :erlang.system_info(:dirty_io_schedulers) * 3
    tasks = for _ <- 1..count, do: Task.async(fn -> ObjectStore.get(ctx.config, ctx.key) end)

    servers =
      for _ <- 1..count do
        assert_receive {:storage_barrier, server, "GET", _key}, 30_000
        server
      end

    assert {:ok, _} = File.read(__ENV__.file)

    Enum.each(servers, &send(&1, {:release_storage, ctx.key}))
    assert Enum.all?(Task.await_many(tasks, 5_000), &(&1 == {:ok, "body"}))
  end

  test "a caller that exits mid-request leaves later requests unaffected", ctx do
    assert {:ok, _etag} = ObjectStore.put(ctx.config, ctx.key, "body")
    owner = self()
    Agent.update(ctx.store, &put_in(&1.barriers[{"GET", ctx.key}], owner))

    {pid, ref} = spawn_monitor(fn -> ObjectStore.get(ctx.config, ctx.key) end)
    assert_receive {:storage_barrier, server, "GET", _key}, 30_000
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^ref, :process, ^pid, :killed}
    send(server, {:release_storage, ctx.key})

    Agent.update(ctx.store, &%{&1 | barriers: %{}})
    assert {:ok, "body"} = ObjectStore.get(ctx.config, ctx.key)
  end

  test "argument errors return immediately and provider errors arrive as replies", ctx do
    assert {:error, :timeout} = ObjectStore.verify(ctx.config, ctx.key, "body", 0)
    assert {:error, :not_found} = ObjectStore.get(ctx.config, ctx.key)
    assert {:ok, etag} = ObjectStore.put_if_none_match(ctx.config, ctx.key, "body")
    assert {:error, :already_exists} = ObjectStore.put_if_none_match(ctx.config, ctx.key, "other")
    assert :not_modified = ObjectStore.get_if_none_match(ctx.config, ctx.key, etag)
    assert {:ok, ^etag, "body"} = ObjectStore.get_if_none_match(ctx.config, ctx.key, nil)
    assert :ok = ObjectStore.delete(ctx.config, ctx.key)
  end
end
