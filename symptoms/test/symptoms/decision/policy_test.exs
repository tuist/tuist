defmodule Symptoms.Decision.PolicyTest do
  use ExUnit.Case, async: true

  alias Symptoms.Decision.Policy

  # November is CET (UTC+1).
  # Monday 11:00 Berlin.
  @day ~U[2026-11-16 10:00:00Z]
  # Monday 18:00 Berlin: 15 hours until the 09:00 board.
  @evening ~U[2026-11-16 17:00:00Z]

  @prices [day_price: 100, night_price: 2000, floor_rate: 50, random: &__MODULE__.never_delay/0]

  def never_delay, do: 0.99

  defp symptom(id, root, p, impact), do: %{id: id, root: root, p: p, impact: impact}

  describe "minutes until review" do
    test "is short during the day and runs to the 09:00 board at night" do
      assert Policy.minutes_until_review(@day) == 60.0
      assert Policy.minutes_until_review(@evening) == 900.0
      # Tuesday 00:00 Berlin → 9 hours.
      assert Policy.minutes_until_review(~U[2026-11-16 23:00:00Z]) == 540.0
      # Saturday 08:00 Berlin: the board is read on weekends too.
      assert Policy.minutes_until_review(~U[2026-11-21 07:00:00Z]) == 60.0
      # July is CEST (UTC+2): 18:00 Berlin is 16:00 UTC.
      assert Policy.minutes_until_review(~U[2026-07-01 16:00:00Z]) == 900.0
    end

    test "night is outside day hours in Berlin" do
      refute Policy.night?(@day)
      assert Policy.night?(@evening)
      # 08:59 Berlin.
      assert Policy.night?(~U[2026-11-16 07:59:00Z])
    end
  end

  describe "day versus night" do
    test "the same symptom pages by day and goes to the board at night" do
      # Day: 0.5 · 4 · 60 = 120 > 100. Night: 0.5 · 4 · 900 = 1800 < 2000.
      symptoms = [symptom(1, :r, 0.5, 4)]

      day = Policy.decide(symptoms, @day, @prices).decisions[1]
      night = Policy.decide(symptoms, @evening, @prices).decisions[1]

      assert %{tier: :page, would_page: true, price: 100, expected_cost: 120.0} = day
      assert %{tier: :board, would_page: false, price: 2000, expected_cost: 1800.0} = night
    end

    test "a larger impact pages at night" do
      # 0.5 · 5 · 900 = 2250 > 2000.
      assert Policy.decide([symptom(1, :r, 0.5, 5)], @evening, @prices).decisions[1].tier == :page
    end
  end

  describe "hard floor" do
    test "unknown impact escalates at high confidence without treating known zero as unknown" do
      opts = Keyword.put(@prices, :day_price, 1.0e12)
      inputs = [symptom(:unknown, :u, 0.95, nil), symptom(:zero, :z, 0.95, 0), symptom(:uncertain, :l, 0.89, nil)]
      result = Policy.decide(inputs, @day, opts)
      assert %{tier: :page, floor: true, expected_cost: nil, delayed_until: nil} = result.decisions[:unknown]
      assert result.decisions[:zero].tier == :board
      assert result.decisions[:uncertain].tier == :board
    end

    test "always pages and is never delayed" do
      opts = Keyword.merge(@prices, day_price: 1.0e12, random: fn -> flunk("floor pages draw no delay") end)

      decision = Policy.decide([symptom(1, :r, 0.95, 60)], @day, opts).decisions[1]

      assert %{tier: :page, floor: true, delayed_until: nil, delay_probability: +0.0} = decision
    end

    test "needs both P ≥ 0.9 and impact above the rate" do
      opts = Keyword.put(@prices, :day_price, 1.0e12)

      assert Policy.decide([symptom(1, :r, 0.89, 60)], @day, opts).decisions[1].tier == :board
      assert Policy.decide([symptom(1, :r, 0.95, 50)], @day, opts).decisions[1].tier == :board
    end
  end

  describe "budget per root" do
    test "a ten-member shared-cause outage is charged one page" do
      root = {:shared_cause, "postgres"}
      symptoms = for i <- 1..10, do: symptom(i, root, 0.6, 1)

      # Root: P 0.6, impact 10 → 0.6 · 10 · 60 = 360 > 100.
      result = Policy.decide(symptoms, @day, @prices)

      assert result.charged_roots == [root]
      assert map_size(result.decisions) == 10
      assert Enum.all?(Map.values(result.decisions), &(&1.tier == :page and &1.root == root))
    end

    test "a root already charged pages without a new charge" do
      root = {:shared_cause, "postgres"}
      opts = Keyword.put(@prices, :charged_roots, [root])

      result = Policy.decide([symptom(1, root, 0.1, 0.1)], @day, opts)

      assert result.charged_roots == []
      assert result.decisions[1].tier == :page
    end
  end

  describe "delay" do
    test "a page below the floor is delayed 10–15 minutes with the probability recorded" do
      # First draw 0.1 < 0.2 delays; second sets 10 + 0.1 · 5 = 10.5 minutes.
      opts = Keyword.put(@prices, :random, fn -> 0.1 end)
      decision = Policy.decide([symptom(1, :r, 0.5, 4)], @day, opts).decisions[1]

      assert decision.tier == :page
      assert decision.delayed_until == DateTime.shift(@day, second: 630)
      assert decision.delay_probability == 0.2
    end

    test "members of a root share one delay draw" do
      parent = self()

      random = fn ->
        send(parent, :draw)
        0.1
      end

      symptoms = for i <- 1..3, do: symptom(i, :r, 0.5, 4)
      result = Policy.decide(symptoms, @day, Keyword.put(@prices, :random, random))

      assert result.decisions |> Map.values() |> Enum.map(& &1.delayed_until) |> Enum.uniq() |> length() == 1
      assert_received :draw
      assert_received :draw
      refute_received :draw
    end

    test "undelayed items still record the probability; audit items do not" do
      symptoms = for i <- 1..6, do: symptom(i, i, 0.1, i)
      result = Policy.decide(symptoms, @day, @prices)

      assert Map.take(result.decisions[6], [:tier, :delayed_until, :delay_probability]) ==
               %{tier: :board, delayed_until: nil, delay_probability: 0.2}

      assert Map.take(result.decisions[1], [:tier, :delay_probability]) == %{tier: :audit, delay_probability: 0.0}
    end
  end

  test "the board takes the top five roots by expected cost" do
    # Costs 0.1 · i · 60 = 6i, all below the day price of 100.
    symptoms = for i <- 1..7, do: symptom(i, i, 0.1, i)
    result = Policy.decide(symptoms, @day, @prices)

    assert result.board == [7, 6, 5, 4, 3]
    assert result.decisions[1].tier == :audit
    assert result.decisions[2].tier == :audit
    assert result.charged_roots == []
  end
end
