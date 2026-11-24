defmodule Symptoms.Decision.Policy do
  @moduledoc """
  Decides page, board or audit (`symptoms/README.md` "Decision"). The
  evaluator calls no model.

  Decisions are made per root, so the budget is charged once per root: a
  shared-cause outage that spawns ten symptoms costs one page. A root's
  P(degraded) is the largest of its members' and its impact is the sum of
  theirs (callers add impact to their root). Every member gets its root's
  decision.

  - Expected cost: `P × impact × minutes until review`.
  - Minutes until review: during day hours (default 09:00–18:00
    Europe/Berlin, every day) `:day_review_minutes` (default 60); otherwise
    the minutes until the next 09:00 board read, about 15 hours from 18:00.
    The board is read every day, weekends included.
  - A root pages when its expected cost exceeds the price of the period
    (`:day_price` or `:night_price`), or at the hard floor: P ≥ 0.9 and
    impact above `:floor_rate` or unknown. Unknown impact leaves expected
    cost nil, not zero; known zero does not use this fallback.
    A root in `:charged_roots` already paged:
    its members page without a new charge or a new delay draw.
  - The other roots are ranked by expected cost; the top five go on the
    board, the rest to audit.
  - A random 20% of pages and board items below the floor are delayed by
    10–15 minutes; `delay_probability` records 0.2 for every item that could
    have been delayed and 0.0 for the others. Floor pages are never delayed.
  """

  @time_zone "Europe/Berlin"

  @type symptom :: %{
          required(:id) => term(),
          required(:root) => term(),
          required(:p) => number(),
          required(:impact) => number() | nil
        }
  @type tier :: :page | :board | :audit
  @type decision :: %{
          tier: tier(),
          would_page: boolean(),
          floor: boolean(),
          root: term(),
          expected_cost: float() | nil,
          price: number(),
          minutes_until_review: float(),
          delayed_until: DateTime.t() | nil,
          delay_probability: float()
        }
  @type result :: %{
          decisions: %{optional(term()) => decision()},
          charged_roots: [term()],
          board: [term()]
        }

  @doc """
  Decides every symptom at `at`.

  Required options: `:day_price`, `:night_price`, `:floor_rate`. Optional:
  `:floor_p` (0.9), `:board_size` (5), `:board_hour` (9), `:day_hours`
  (`{9, 18}`, local start inclusive, end exclusive), `:day_review_minutes`
  (60), `:delay_share` (0.2), `:delay_minutes` (`{10, 15}`), `:charged_roots`
  (roots already paged), and `:random`, a zero-arity function returning a
  float in `[0, 1)` (default `:rand.uniform/0`).

  Returns the decision per symptom id, the roots newly charged a page and
  the board's roots in rank order.
  """
  @spec decide([symptom()], DateTime.t(), keyword()) :: result()
  def decide(symptoms, at, opts) do
    minutes = minutes_until_review(at, opts)
    price = if night?(at, opts), do: Keyword.fetch!(opts, :night_price), else: Keyword.fetch!(opts, :day_price)
    floor_rate = Keyword.fetch!(opts, :floor_rate)
    floor_p = Keyword.get(opts, :floor_p, 0.9)
    already_charged = MapSet.new(Keyword.get(opts, :charged_roots, []))

    roots =
      symptoms
      |> Enum.group_by(& &1.root)
      |> Enum.map(fn {root, members} ->
        p = members |> Enum.map(& &1.p) |> Enum.max()
        rates = Enum.map(members, & &1.impact)
        impact = if Enum.any?(rates, &is_nil/1), do: nil, else: Enum.sum(rates)
        cost = if is_number(impact), do: p * impact * minutes * 1.0
        # Unknown operational impact is not a measured zero. Escalate a
        # confident detection without inventing a conversion to requests.
        floor = p >= floor_p and (is_nil(impact) or impact > floor_rate)

        %{
          root: root,
          members: members,
          cost: cost,
          floor: floor,
          page: floor or exceeds_price?(cost, price) or MapSet.member?(already_charged, root),
          charged: MapSet.member?(already_charged, root)
        }
      end)
      |> Enum.sort_by(&{-(&1.cost || 0.0), inspect(&1.root)})

    {pages, others} = Enum.split_with(roots, & &1.page)
    {board, audit} = Enum.split(others, Keyword.get(opts, :board_size, 5))

    tiered =
      Enum.map(pages, &{&1, :page}) ++ Enum.map(board, &{&1, :board}) ++ Enum.map(audit, &{&1, :audit})

    # One delay draw per root, shared by its members.
    decisions =
      Enum.reduce(tiered, %{}, fn {root, tier}, acc ->
        decision = decision(root, tier, price, minutes, at, opts)
        Enum.reduce(root.members, acc, &Map.put(&2, &1.id, decision))
      end)

    %{
      decisions: decisions,
      charged_roots: pages |> Enum.reject(& &1.charged) |> Enum.map(& &1.root),
      board: Enum.map(board, & &1.root)
    }
  end

  defp exceeds_price?(cost, price), do: is_number(cost) and cost > price

  defp decision(root, tier, price, minutes, at, opts) do
    {delayed_until, probability} = delay(root, tier, at, opts)

    %{
      tier: tier,
      would_page: tier == :page,
      floor: root.floor,
      root: root.root,
      expected_cost: root.cost,
      price: price,
      minutes_until_review: minutes,
      delayed_until: delayed_until,
      delay_probability: probability
    }
  end

  defp delay(%{floor: true}, _tier, _at, _opts), do: {nil, 0.0}
  defp delay(%{charged: true}, _tier, _at, _opts), do: {nil, 0.0}
  defp delay(_root, :audit, _at, _opts), do: {nil, 0.0}

  defp delay(_root, _tier, at, opts), do: draw_delay(at, opts)

  @doc """
  One delay draw at `at` for an item that may be delayed: `{delayed_until,
  delay_share}`, with `delayed_until` 10–15 minutes after `at` with
  probability `:delay_share` (0.2), else `nil`. Takes the options of
  `decide/3` (`:random`, `:delay_share`, `:delay_minutes`).
  """
  @spec draw_delay(DateTime.t(), keyword()) :: {DateTime.t() | nil, float()}
  def draw_delay(at, opts) do
    random = Keyword.get(opts, :random, &:rand.uniform/0)
    share = Keyword.get(opts, :delay_share, 0.2)
    {low, high} = Keyword.get(opts, :delay_minutes, {10, 15})

    if random.() < share do
      seconds = round((low + random.() * (high - low)) * 60)
      {DateTime.shift(at, second: seconds), share}
    else
      {nil, share}
    end
  end

  @doc "Whether `at` falls outside day hours in Europe/Berlin (see `decide/3` options)."
  @spec night?(DateTime.t(), keyword()) :: boolean()
  def night?(at, opts \\ []) do
    {start_hour, end_hour} = Keyword.get(opts, :day_hours, {9, 18})
    local = DateTime.shift_zone!(at, @time_zone)
    local.hour < start_hour or local.hour >= end_hour
  end

  @doc """
  Minutes until a person reviews the board: `:day_review_minutes` during day
  hours, otherwise the minutes until the next `:board_hour` (09:00) in
  Europe/Berlin.
  """
  @spec minutes_until_review(DateTime.t(), keyword()) :: float()
  def minutes_until_review(at, opts \\ []) do
    if night?(at, opts) do
      board_hour = Keyword.get(opts, :board_hour, 9)
      local = DateTime.shift_zone!(at, @time_zone)
      date = if local.hour < board_hour, do: DateTime.to_date(local), else: Date.add(DateTime.to_date(local), 1)
      {:ok, read} = DateTime.new(date, Time.new!(board_hour, 0, 0), @time_zone)
      DateTime.diff(read, at, :second) / 60
    else
      Keyword.get(opts, :day_review_minutes, 60) * 1.0
    end
  end
end
