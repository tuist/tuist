defmodule LuftServer.LoungesConcurrencyTest do
  use ExUnit.Case, async: false

  import Ecto.Query

  alias Ecto.Adapters.SQL.Sandbox
  alias LuftServer.Lounges
  alias LuftServer.Lounges.Lounge
  alias LuftServer.Lounges.Message
  alias LuftServer.Lounges.Presence
  alias LuftServer.Repo
  alias LuftServer.Tuist.Scope

  setup_all do
    if !Process.whereis(LuftServer.PubSub),
      do: start_supervised!({Phoenix.PubSub, name: LuftServer.PubSub})

    if !Process.whereis(Presence), do: start_supervised!(Presence)
    :ok
  end

  setup do
    # Real independent PostgreSQL transactions, not concurrent tasks sharing a
    # sandbox connection (which would serialize before reaching the row lock).
    :ok = Sandbox.checkout(Repo, sandbox: false)
    account_id = 5_000_000_000 + System.unique_integer([:positive])

    scope = %Scope{
      user_id: 1,
      account_id: account_id,
      organization_id: 10,
      people: [%{id: 1, handle: "one", active: true}, %{id: 2, handle: "two", active: true}],
      can_create_threads: false
    }

    on_exit(fn ->
      :ok = Sandbox.checkout(Repo, sandbox: false)
      Repo.delete_all(from l in Lounge, where: l.account_id == ^account_id)
      Sandbox.checkin(Repo)
    end)

    %{scope: scope}
  end

  defp race(fun) do
    parent = self()
    # The parent is idle at the barrier; leave all four connections available
    # for the independent writers even on the two-scheduler CI runner.
    :ok = Sandbox.checkin(Repo)

    try do
      tasks =
        for n <- 1..4 do
          Task.async(fn ->
            :ok = Sandbox.checkout(Repo, sandbox: false)
            send(parent, {:ready, self()})

            try do
              receive do
                :go -> fun.(n)
              after
                5000 -> raise "race did not start"
              end
            after
              Sandbox.checkin(Repo)
            end
          end)
        end

      ready =
        for _ <- tasks do
          receive do
            {:ready, pid} -> pid
          after
            5000 -> flunk("database worker did not become ready")
          end
        end

      Enum.each(ready, &send(&1, :go))
      Enum.map(tasks, &Task.await(&1, 15_000))
    after
      :ok = Sandbox.checkout(Repo, sandbox: false)
    end
  end

  test "racing creates and DM starts return exactly one conversation", %{scope: scope} do
    attrs = %{"name" => "race", "request_id" => Ecto.UUID.generate()}
    results = race(fn _ -> Lounges.create(scope, attrs) end)
    assert Enum.all?(results, &match?({:ok, _}, &1))
    assert results |> Enum.map(fn {:ok, row} -> row.id end) |> Enum.uniq() |> length() == 1

    attrs = %{"user_ids" => [2], "request_id" => Ecto.UUID.generate()}
    results = race(fn _ -> Lounges.direct(scope, attrs) end)
    assert Enum.all?(results, &match?({:ok, _}, &1))
    assert results |> Enum.map(fn {:ok, row} -> row.id end) |> Enum.uniq() |> length() == 1
  end

  test "independent writers allocate contiguous positions, deduplicate and never regress reads",
       %{scope: scope} do
    {:ok, lounge} =
      Lounges.create(scope, %{"name" => "messages", "request_id" => Ecto.UUID.generate()})

    results =
      race(fn n ->
        Lounges.message(scope, lounge.id, %{
          "content" => "message #{n}",
          "request_id" => Ecto.UUID.generate()
        })
      end)

    assert Enum.all?(results, &match?({:ok, _}, &1))
    attrs = %{"content" => "retry", "request_id" => Ecto.UUID.generate()}

    assert fn _ -> Lounges.message(scope, lounge.id, attrs) end
           |> race()
           |> Enum.all?(&match?({:ok, _}, &1))

    assert Repo.all(
             from m in Message,
               where: m.lounge_id == ^lounge.id,
               order_by: m.position,
               select: m.position
           ) == [1, 2, 3, 4, 5]

    request_id = Ecto.UUID.generate()

    conflicts =
      race(fn n ->
        Lounges.message(scope, lounge.id, %{
          "content" => "conflicting #{n}",
          "request_id" => request_id
        })
      end)

    assert Enum.count(conflicts, &match?({:ok, _}, &1)) == 1
    assert Enum.count(conflicts, &(&1 == {:error, :request_conflict})) == 3
    assert {:ok, %{last_position: 6}} = Lounges.get(scope, lounge.id)

    reader = %{scope | user_id: 2}

    assert fn n -> Lounges.read(reader, lounge.id, n) end
           |> race()
           |> Enum.all?(&match?({:ok, _}, &1))

    assert {:ok, %{read_position: 4}} = Lounges.get(reader, lounge.id)
  end
end
