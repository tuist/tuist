defmodule Pulse.Loki.TailLifecycleTest do
  use Pulse.Test.Case, async: true

  alias Pulse.Loki.Tail
  alias Pulse.Runtime

  for max <- [1, 3] do
    @tag max_tails: max
    test "concurrent joins cannot exceed the per-tenant limit of #{max}", %{max_tails: max} do
      parent = self()
      runtime = Runtime.current()

      workers =
        for i <- 1..32 do
          start_supervised!(
            {Task,
             fn ->
               Runtime.with(runtime, fn ->
                 send(parent, {:ready, self()})
                 receive do: (:join -> :ok)
                 send(parent, {:joined, self(), Tail.join("concurrent", max)})
                 receive do: (:leave -> Tail.leave("concurrent"))
               end)
             end},
            id: {:join, i}
          )
        end

      for worker <- workers, do: assert_receive({:ready, ^worker}, 5_000)
      for worker <- workers, do: send(worker, :join)
      results = for _ <- workers, do: receive_join()

      assert Enum.count(results, &match?({_, {:ok, _}}, &1)) == max
      assert Enum.count(results, &match?({_, {:error, :too_many_tails}}, &1)) == 32 - max
      assert length(Tail.tailers("concurrent")) == max
      assert {:ok, _} = Tail.join("other-tenant", 1)
    end
  end

  test "rejoining is idempotent and leaving releases admission immediately" do
    assert {:ok, follower} = Tail.join("rejoin", 1)
    assert {:ok, ^follower} = Tail.join("rejoin", 1)
    assert Tail.tailers("rejoin") == [self()]
    assert :ok = Tail.leave("rejoin")
    assert :ok = Tail.leave("rejoin")
    assert Tail.tailers("rejoin") == []
    assert {:ok, ^follower} = Tail.join("rejoin", 1)
  end

  test "a terminated caller does not retain admission" do
    parent = self()
    runtime = Runtime.current()

    worker =
      start_supervised!(
        {Task,
         fn ->
           Runtime.with(runtime, fn ->
             send(parent, {:joined, self(), Tail.join("terminated", 1)})
             receive do: (:finish -> :ok)
           end)
         end}
      )

    assert {^worker, {:ok, follower}} = receive_join()
    assert {:error, :too_many_tails} = Tail.join("terminated", 1)
    ref = Process.monitor(worker)
    send(worker, :finish)
    assert_receive {:DOWN, ^ref, :process, ^worker, :normal}, 5_000
    assert {:ok, ^follower} = Tail.join("terminated", 1)
  end

  test "unavailable supervision rejects joins without leaving a registration" do
    assert :ok = stop_supervised(Tail)
    assert {:error, :tail_unavailable} = Tail.join("unavailable", 1)
    assert :ok = Tail.leave("unavailable")
    start_supervised!(Tail)
    assert {:ok, _} = Tail.join("unavailable", 1)
    assert Tail.tailers("unavailable") == [self()]
  end

  test "failed follower startup releases the reserved slot" do
    supervisor = Runtime.whereis(Tail)
    children = Supervisor.which_children(supervisor)
    followers = Runtime.whereis(Tail.Followers)
    {id, ^followers, _, _} = Enum.find(children, fn {_id, pid, _, _} -> pid == followers end)
    assert :ok = Supervisor.terminate_child(supervisor, id)
    assert {:error, :tail_unavailable} = Tail.join("startup-failure", 1)
    assert Tail.tailers("startup-failure") == []
    assert {:ok, _} = Supervisor.restart_child(supervisor, id)
    assert {:ok, _} = Tail.join("startup-failure", 1)
  end

  defp receive_join do
    assert_receive {:joined, worker, result}, 5_000
    {worker, result}
  end
end
