defmodule Symptoms.BoardTest do
  use Symptoms.DataCase

  alias Symptoms.Board
  alias Symptoms.Log
  alias Symptoms.Store.Symptom

  @at ~U[2026-11-16 08:00:00.000000Z]
  defp board_symptom(name, cost) do
    id = Log.uuid7(@at)

    symptom =
      Repo.insert!(%Symptom{
        id: id,
        symptom_key: name,
        root_key: "60:entity:#{name}",
        phenomenon: "request_errors",
        state: "open",
        tier: "board",
        max_tier: "board",
        expected_cost: cost,
        opened_at: @at
      })

    document = %{
      "tier" => "board",
      "transition" => "opened",
      "title" => "request errors on #{name}",
      "entity" => %{"environment" => "production", "service" => "tuist-server", "kind" => "route", "key" => name},
      "root" => %{"root_symptom_id" => id, "member_symptom_ids" => [], "shared_cause" => false}
    }

    Repo.transaction(fn -> Log.append!(symptom, document, @at) end)
    id
  end

  def always_delay, do: 0.0

  describe "board push" do
    setup do
      # ln costs: 6.91, 6.80, 6.68, 6.55, 4.61, 4.50: the board is the first five.
      ids =
        for {name, cost} <- [one: 1000, two: 900, three: 800, four: 700, five: 100, six: 90],
            do: board_symptom("#{name}", cost * 1.0)

      %{ids: ids}
    end

    test "the top five by expected cost, marked and served", %{ids: ids} do
      assert Board.push(@at) == Enum.take(ids, 5)
      assert %{"board" => %{"rank" => 1, "date" => "2026-11-16"}, "transition" => "annotated"} = Log.latest(hd(ids))
      assert Log.latest(List.last(ids))["board"] == nil
      assert Enum.take(ids, 5) == Enum.map(Log.board(5), & &1["symptom_id"])
    end

    test "the push draws and persists each item's delay, which /board honours", %{ids: ids} do
      top = Enum.take(ids, 5)

      # DataCase's draw is 0.99 ≥ 0.2: nothing delayed, q = 0.2 recorded.
      assert Board.push(@at) == top

      for id <- top do
        assert %{delay_probability: 0.2, delayed_until: nil} = Repo.get!(Symptom, id)
        assert %{"delay_probability" => 0.2, "delayed_until" => nil} = Log.latest(id)["board"]
      end

      # A draw of 0.0 < 0.2 delays every item by 10 + 0.0 · 5 = 10 minutes.
      Application.put_env(:symptoms, :policy, random: {__MODULE__, :always_delay, []})
      now = DateTime.utc_now()
      assert Board.push(now) == top
      until = DateTime.shift(now, minute: 10)

      assert %{delay_probability: 0.2, delayed_until: ^until} = Repo.get!(Symptom, hd(top))
      assert Log.latest(hd(top))["board"]["delayed_until"] == DateTime.to_iso8601(until)
      # Served only once the delay has passed.
      assert Log.board(5) == []
      assert Enum.map(Log.board(5, DateTime.shift(until, second: 1)), & &1["symptom_id"]) == top
    end
  end
end
