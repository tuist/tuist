defmodule Tuist.Shards.BinPacker do
  @moduledoc """
  LPT (Longest Processing Time) bin-packing algorithm for distributing
  test units across shards.
  """

  @default_min_shards 1
  @default_max_shards 10

  @doc """
  Packs units into `shard_count` shards using the LPT algorithm.

  Sorts units by duration descending, then assigns each to the
  least-loaded shard.

  Returns a list of `{index, units, total_duration_ms}` tuples,
  one per shard. Empty shards are included with empty unit lists.

  ## Example

      iex> BinPacker.pack([{"AppTests", 8000}, {"CoreTests", 3000}, {"UITests", 5000}], 2)
      [
        {0, [{"AppTests", 8000}], 8000},
        {1, [{"UITests", 5000}, {"CoreTests", 3000}], 8000}
      ]
  """
  def pack(units, shard_count) when is_list(units) and is_integer(shard_count) and shard_count > 0 do
    empty_shards = Enum.map(0..(shard_count - 1), &{&1, [], 0})

    units
    |> Enum.sort_by(&elem(&1, 1), :desc)
    |> Enum.reduce(empty_shards, fn {name, duration}, shards ->
      min_index = shards |> Enum.min_by(&elem(&1, 2)) |> elem(0)

      List.update_at(shards, min_index, fn {index, units, total} ->
        {index, [{name, duration} | units], total + duration}
      end)
    end)
    |> Enum.map(fn {index, units, total} -> {index, Enum.reverse(units), total} end)
  end

  @doc """
  Determines the optimal shard count from constraints.

  Options:
    - `:min` - minimum number of shards (default: #{@default_min_shards})
    - `:max` - maximum number of shards (default: #{@default_max_shards})
    - `:total` - exact shard count (overrides min/max auto-calculation)
    - `:max_duration` - target maximum duration per shard in ms

  When `:total` is given, returns it directly (clamped to unit count).
  When `:max_duration` is given, calculates the minimum shards needed
  so no shard exceeds that duration (estimated).
  Otherwise returns `:max`.
  """
  def determine_shard_count(units, opts \\ []) when is_list(units) do
    total = Keyword.get(opts, :total)
    min_shards = Keyword.get(opts, :min, @default_min_shards)
    max_shards = Keyword.get(opts, :max, @default_max_shards)
    max_duration = Keyword.get(opts, :max_duration)

    unit_count = length(units)

    cond do
      unit_count == 0 ->
        1

      total != nil ->
        total |> max(1) |> min(unit_count)

      max_duration != nil && max_duration > 0 ->
        total_duration = units |> Enum.map(fn {_name, d} -> d end) |> Enum.sum()
        needed = (total_duration / max_duration) |> ceil() |> max(min_shards) |> min(max_shards)
        min(needed, unit_count)

      true ->
        max_shards |> max(min_shards) |> min(unit_count)
    end
  end
end
