defmodule LuftServer.Agents.LeaseTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias LuftServer.Agents.Lease
  alias LuftServer.Repo

  setup do
    if !Process.whereis(LuftServer.PubSub),
      do: start_supervised!({Phoenix.PubSub, name: LuftServer.PubSub})

    owner = Sandbox.start_owner!(Repo, shared: true)
    on_exit(fn -> Sandbox.stop_owner(owner) end)
    :ok
  end

  test "claim is capacity bounded, exclusive and raises epochs on takeover" do
    ids = for _ <- 1..5, do: Ecto.UUID.generate()
    Enum.each(ids, &Lease.want(&1, "fake", min_epoch: 5))
    first = Lease.claim("one", 2)
    assert length(first) == 2
    assert Enum.all?(first, &(&1.epoch == 6))
    second = Lease.claim("two", 10)
    assert length(second) == 3
    assert Enum.sort(Enum.map(first ++ second, & &1.id)) == Enum.sort(ids)
    assert Lease.claim("three", 1) == []
    [%{id: id, epoch: epoch} | _] = first
    expire(id)
    assert [%{id: ^id, epoch: next}] = Lease.claim("three", 1)
    assert next == epoch + 1
    assert Lease.renew("one", [{id, epoch}]) == %{}
    assert :ok = Lease.release(id, epoch)

    assert %{rows: [["three", ^next]]} =
             Repo.query!("SELECT host, epoch FROM agent_sessions WHERE id=$1", [id])
  end

  test "want_seq fences idle release and delayed retry is overridden by fresh work" do
    id = Ecto.UUID.generate()
    Lease.want(id, "fake")
    [%{epoch: epoch}] = Lease.claim("one", 1)
    assert %{{^id, ^epoch} => seen} = Lease.renew("one", [{id, epoch}])
    Lease.want(id, "fake")
    Lease.release(id, epoch, wanted: false, seen: seen)
    assert [%{epoch: next}] = Lease.claim("two", 1)
    Lease.release(id, next, delay_ms: 60_000)
    assert Lease.claim("three", 1) == []
    Lease.want(id, "fake")
    assert [%{epoch: final}] = Lease.claim("three", 1)
    %{{^id, ^final} => seq} = Lease.renew("three", [{id, final}])
    Lease.release(id, final, wanted: false, seen: seq)
    assert Lease.claim("four", 1) == []
  end

  test "expired leases cannot renew; deleted sessions cannot be claimed even after another want" do
    id = Ecto.UUID.generate()
    Lease.want(id, "fake")
    [%{epoch: epoch}] = Lease.claim("one", 1)
    expire(id)
    assert Lease.renew("one", [{id, epoch}]) == %{}

    Repo.query!(
      "UPDATE agent_sessions SET deleted_at=CURRENT_TIMESTAMP, wanted=false WHERE id=$1",
      [id]
    )

    Lease.want(id, "fake")
    assert Lease.claim("two", 1) == []
  end

  test "concurrent hosts claim disjoint sets" do
    ids = for _ <- 1..8, do: Ecto.UUID.generate()
    # Separate real connections, not the shared sandbox's serialized queries.
    Sandbox.unboxed_run(Repo, fn ->
      try do
        Enum.each(ids, &Lease.want(&1, "fake"))

        claims =
          1..4
          |> Task.async_stream(fn n ->
            Sandbox.unboxed_run(Repo, fn -> Lease.claim("host-#{n}", 2) end)
          end)
          |> Enum.flat_map(fn {:ok, claims} -> claims end)

        assert Enum.sort(Enum.map(claims, & &1.id)) == Enum.sort(ids)
      after
        Repo.query!("DELETE FROM agent_sessions WHERE id=ANY($1)", [ids])
      end
    end)
  end

  defp expire(id) do
    Repo.query!(
      "UPDATE agent_sessions SET lease_expires_at=CURRENT_TIMESTAMP - interval '1 second' WHERE id=$1",
      [id]
    )
  end
end
