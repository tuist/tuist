defmodule Tuist.BrowserTelemetry.ReceiptsTest do
  use ExUnit.Case, async: false

  import Ecto.Query

  alias Ecto.Adapters.SQL.Sandbox
  alias Tuist.BrowserTelemetry.Receipts
  alias Tuist.Repo

  setup do
    # Real independent connections are needed to exercise replica races.
    owner = Sandbox.start_owner!(Repo, sandbox: false)
    keys = for _ <- 1..3, do: :crypto.strong_rand_bytes(32)

    on_exit(fn ->
      Repo.delete_all(from(r in "browser_telemetry_receipts", where: r.key in ^keys))
      Sandbox.stop_owner(owner)
    end)

    %{keys: keys}
  end

  test "only acknowledged reports become duplicates", %{keys: [key | _]} do
    assert {:error, :timeout} =
             Receipts.deliver([key], fn seen ->
               assert MapSet.size(seen) == 0
               {:error, :timeout}
             end)

    assert {:ok, :first} =
             Receipts.deliver([key], fn seen ->
               assert MapSet.size(seen) == 0
               {:ok, :first}
             end)

    assert {:ok, :retry} =
             Receipts.deliver([key], fn seen ->
               assert MapSet.member?(seen, key)
               {:ok, :retry}
             end)
  end

  test "exceptions release claims", %{keys: [key | _]} do
    assert_raise RuntimeError, "receiver failed", fn ->
      Receipts.deliver([key], fn _ -> raise "receiver failed" end)
    end

    assert {:ok, 0} = Receipts.deliver([key], &{:ok, MapSet.size(&1)})
  end

  test "another connection cannot forward an in-flight report or retain partial claims", %{keys: [a, b | _]} do
    parent = self()

    first =
      Task.async(fn ->
        Receipts.deliver([a], fn _ ->
          send(parent, :forwarding)
          receive do: (:complete -> {:ok, :first})
        end)
      end)

    assert_receive :forwarding, 2_000
    second = Task.async(fn -> Receipts.deliver([b, a], fn _ -> flunk("duplicate forwarded") end) end)
    assert {:error, :in_progress} = Task.await(second)
    assert {:ok, 0} = Receipts.deliver([b], &{:ok, MapSet.size(&1)})
    send(first.pid, :complete)
    assert {:ok, :first} = Task.await(first)
    assert {:ok, 2} = Receipts.deliver([a, b], &{:ok, MapSet.size(&1)})
  end

  test "expired claims can be recovered without the previous owner releasing the new lease", %{keys: [key | _]} do
    parent = self()

    abandoned =
      Task.async(fn ->
        Receipts.deliver([key], fn _ ->
          send(parent, :claimed)
          receive do: (:fail -> {:error, :timeout})
        end)
      end)

    assert_receive :claimed, 2_000

    Repo.update_all(
      from(r in "browser_telemetry_receipts",
        where: r.key == ^key,
        update: [set: [expires_at: fragment("now() - interval '1 second'")]]
      ),
      []
    )

    assert {:ok, 0} = Receipts.deliver([key], &{:ok, MapSet.size(&1)})
    send(abandoned.pid, :fail)
    assert {:error, :timeout} = Task.await(abandoned)
    assert {:ok, 1} = Receipts.deliver([key], &{:ok, MapSet.size(&1)})
  end

  test "confirmed receipts live for 48 hours and pruning retains active receipts", %{keys: [a, b | _]} do
    assert {:ok, 0} = Receipts.deliver([a, b], &{:ok, MapSet.size(&1)})

    %{rows: [[seconds]]} =
      Repo.query!(
        "SELECT EXTRACT(EPOCH FROM expires_at - completed_at)::bigint FROM browser_telemetry_receipts WHERE key = $1",
        [a]
      )

    assert seconds == 172_800

    Repo.update_all(
      from(r in "browser_telemetry_receipts",
        where: r.key == ^a,
        update: [set: [expires_at: fragment("now() - interval '1 second'")]]
      ),
      []
    )

    assert Receipts.prune() >= 1
    refute Repo.exists?(from(r in "browser_telemetry_receipts", where: r.key == ^a))
    assert Repo.exists?(from(r in "browser_telemetry_receipts", where: r.key == ^b))
  end

  test "receipts expire without waiting for the pruning worker", %{keys: [key | _]} do
    assert {:ok, 0} = Receipts.deliver([key], &{:ok, MapSet.size(&1)})

    Repo.update_all(
      from(r in "browser_telemetry_receipts",
        where: r.key == ^key,
        update: [set: [expires_at: fragment("now() - interval '1 second'")]]
      ),
      []
    )

    assert {:ok, 0} = Receipts.deliver([key], &{:ok, MapSet.size(&1)})
  end
end
