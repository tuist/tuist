defmodule Symptoms.LockOrderTest do
  # Every writer of revisions takes the log's advisory lock (`Log.lock!/0`)
  # before it locks or writes a symptom row, and reads the symptom only
  # under that lock.
  use Symptoms.DataCase
  use Mimic

  alias Symptoms.Contrast
  alias Symptoms.Lifecycle
  alias Symptoms.Log
  alias Symptoms.State
  alias Symptoms.Store
  alias Symptoms.Store.Symptom

  @at ~U[2026-11-16 10:00:00.000000Z]
  @lock 7_301_116_190_001

  # Whether this connection holds `Log.lock!/0`'s lock: a one-bigint advisory
  # key shows in pg_locks as classid (high 32 bits), objid (low) and objsubid 1.
  defp log_lock_held? do
    import Bitwise

    %{rows: [[n]]} =
      Repo.query!(
        "SELECT count(*) FROM pg_locks WHERE locktype = 'advisory' AND pid = pg_backend_pid() " <>
          "AND classid = $1 AND objid = $2 AND objsubid = 1",
        [@lock >>> 32, @lock &&& 0xFFFFFFFF]
      )

    n > 0
  end

  defp symptom(attrs \\ []) do
    sym =
      Repo.insert!(
        struct(
          %Symptom{
            id: Log.uuid7(@at),
            symptom_key: "k",
            root_key: "60:entity:1",
            phenomenon: "request_errors",
            state: "open",
            tier: "board",
            max_tier: "board",
            max_score: 7.0,
            opened_at: @at
          },
          attrs
        )
      )

    document = %{
      "state" => "open",
      "tier" => "board",
      "transition" => "opened",
      "evidence" => %{"series_refs" => [], "example_ids" => [], "masked_excerpts" => []},
      "root" => %{"root_symptom_id" => sym.id, "member_symptom_ids" => [], "shared_cause" => false}
    }

    {:ok, sym} = Repo.transaction(fn -> Log.append!(sym, Map.merge(document, attrs[:doc] || %{}), @at) end)
    sym
  end

  # On the first `Log.lock!/0`, before taking the lock, another writer
  # resolves `id`: the latest moment a reader before the lock could miss.
  defp resolve_before_lock(id) do
    stub(Log, :lock!, fn ->
      if Process.put(:resolved, true) == nil do
        call_original(Log, :lock!, [])
        sym = Repo.get!(Symptom, id)
        Repo.update_all(from(s in Symptom, where: s.id == ^id), set: [state: "resolved", resolved_at: @at])

        document =
          sym.document
          |> Map.drop(~w(seq revision schema_version symptom_id))
          |> Map.merge(%{"state" => "resolved", "transition" => "resolved"})

        Log.append!(%{sym | state: "resolved"}, document, @at)
      end

      call_original(Log, :lock!, [])
    end)
  end

  test "the state read-back takes the log lock before its first row write" do
    stub(Repo, :insert_all, fn schema, rows, opts ->
      if Process.put(:first_write, true) == nil, do: send(self(), {:locked, log_lock_held?()})
      call_original(Repo, :insert_all, [schema, rows, opts])
    end)

    outcome = %{
      "symptom_id" => Log.uuid7(@at),
      "outcome" => "bad",
      "confirmed_at" => "2026-11-16T10:00:00.000000Z",
      "change_seq" => 1
    }

    State.apply_page(%{"outcomes" => [outcome], "next" => 1}, 0, @at)
    assert_received {:locked, true}
  end

  test "a window takes the log lock before its first symptom write, even with no open symptom" do
    route = %{service: "tuist-server", kind: "route", key: "GET /lock"}
    ids = Store.resolve_entities([route], DateTime.shift(@at, day: -1))
    id = ids[Store.entity_tuple(route)]

    stub(Repo, :insert!, fn struct ->
      if match?(%Symptom{}, struct) and Process.put(:first_write, true) == nil,
        do: send(self(), {:locked, log_lock_held?()})

      call_original(Repo, :insert!, [struct])
    end)

    # x = 7 ≥ h = 6 opens a symptom in this window.
    score = %{x: 7.0, phenomena: [], impact_unit: nil, impact_rate: 0.0, examples: []}
    assert %{opened: [_]} = Lifecycle.step(60, @at, %{id => score}, @at)
    assert_received {:locked, true}
  end

  test "an outcome attached after a resolution does not roll the symptom back to open" do
    sym = symptom()
    resolve_before_lock(sym.id)

    outcome = %{
      "symptom_id" => sym.id,
      "outcome" => "bad",
      "confirmed_at" => "2026-11-16T10:30:00.000000Z",
      "change_seq" => 1
    }

    State.apply_page(%{"outcomes" => [outcome], "next" => 1}, 0, @at)

    latest = Log.latest(sym.id)
    assert latest["outcome"]["outcome"] == "bad"
    assert latest["state"] == "resolved"
  end

  test "a contrast written after a resolution does not roll the symptom back to open" do
    route = %{service: "tuist-server", kind: "span_server", key: "GET /c"}
    ids = Store.resolve_entities([route], DateTime.shift(@at, day: -1))
    entity_id = ids[Store.entity_tuple(route)]
    sym = symptom(entity_id: entity_id)

    doc = %{"root" => %{"root_symptom_id" => sym.id, "member_symptom_ids" => [], "shared_cause" => true}}
    Repo.update_all(from(s in Symptom, where: s.id == ^sym.id), set: [document: Map.merge(sym.document, doc)])

    stub(Symptoms.Sources.Pulse, :query, fn sql, _opts ->
      if sql =~ "GROUP BY value",
        do: {:ok, [%{"value" => "pod-a", "spans" => 10, "errors" => 9}]},
        else: {:ok, [%{"spans" => 100, "errors" => 10}]}
    end)

    resolve_before_lock(sym.id)
    assert [_] = Contrast.annotate([sym.id], @at)

    latest = Log.latest(sym.id)
    assert latest["evidence"]["attribute_contrast"]
    assert latest["state"] == "resolved"
  end
end
