defmodule TuistWeb.RateLimit.RedisPoolTest do
  use ExUnit.Case, async: true

  alias TuistWeb.RateLimit.RedisPool

  @moduletag :capture_log

  setup do
    name = Module.concat(__MODULE__, "Pool#{System.unique_integer([:positive])}")

    start_supervised!(%{
      id: name,
      start: {RedisPool, :start_link, [name, [url: "redis://127.0.0.1:0"]]},
      type: :supervisor
    })

    %{name: name}
  end

  test "starts exactly four independently supervised clients", %{name: name} do
    children = Supervisor.which_children(name)
    assert length(children) == 4
    assert Enum.all?(children, fn {_id, pid, :worker, _} -> is_pid(pid) and Process.alive?(pid) end)
  end

  test "routes by caller rather than key without a checkout mailbox", %{name: name} do
    children = Map.new(Supervisor.which_children(name), fn {id, pid, _, _} -> {id, pid} end)

    results =
      1..64
      |> Task.async_stream(fn _ -> {self(), RedisPool.connection(name)} end)
      |> Enum.map(fn {:ok, result} -> result end)

    for {caller, client} <- results do
      assert client == Map.fetch!(children, :erlang.phash2(caller, 4))
    end

    assert RedisPool.connection(name) == RedisPool.connection(name)
  end

  test "a restarted client is resolved again without disturbing other clients", %{name: name} do
    before = Map.new(Supervisor.which_children(name), fn {id, pid, _, _} -> {id, pid} end)
    partition = :erlang.phash2(self(), 4)
    old_client = RedisPool.connection(name)
    assert old_client == Map.fetch!(before, partition)

    assert :ok = Supervisor.terminate_child(name, partition)
    assert {:ok, new_client} = Supervisor.restart_child(name, partition)
    assert new_client != old_client
    assert RedisPool.connection(name) == new_client

    after_restart = Map.new(Supervisor.which_children(name), fn {id, pid, _, _} -> {id, pid} end)
    assert Map.delete(after_restart, partition) == Map.delete(before, partition)
  end

  test "a stopped pool reports process unavailability", %{name: name} do
    assert :ok = stop_supervised(name)
    assert {:noproc, _} = catch_exit(RedisPool.connection(name))
  end

  test "child specifications retain distinct supervisor identities" do
    assert %{id: __MODULE__, type: :supervisor, shutdown: 5000, start: {__MODULE__, :start_link, [[]]}} =
             RedisPool.child_spec(__MODULE__, [])
  end
end
