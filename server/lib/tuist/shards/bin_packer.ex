defmodule Tuist.Shards.BinPacker do
  @moduledoc """
  LPT (Longest Processing Time) bin-packing algorithm for distributing
  test units across shards.
  """

  @default_min_shards 1
  @default_max_shards 10

  # Module-affinity packing is accepted only when its slowest shard stays within
  # this factor of the duration-optimal (plain LPT) packing's slowest shard, so
  # grouping a module's suites onto one shard never meaningfully hurts balance.
  @affinity_balance_tolerance 1.05

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
  Like `pack/2`, but keeps units that share a group (per `group_fn`) on the same
  shard so a shard pulls fewer per-module artifacts. Falls back to the plain
  duration-optimal packing whenever grouping would make the slowest shard more
  than `#{@affinity_balance_tolerance}`x the optimal one, so balance is never
  meaningfully sacrificed for affinity.
  """
  def pack(units, shard_count, group_fn)
      when is_list(units) and is_integer(shard_count) and shard_count > 0 and is_function(group_fn, 1) do
    balanced = pack(units, shard_count)
    grouped = pack_with_affinity(units, shard_count, group_fn)

    if makespan(grouped) <= makespan(balanced) * @affinity_balance_tolerance do
      grouped
    else
      balanced
    end
  end

  # Keeps each group's units together as a single packable item (so the whole
  # module lands on one shard), except for a group whose total duration already
  # exceeds the per-shard target — those are packed unit-by-unit so a single
  # heavy module can't blow out one shard.
  defp pack_with_affinity(units, shard_count, group_fn) do
    total_duration = units |> Enum.map(&elem(&1, 1)) |> Enum.sum()
    target = total_duration / shard_count

    items =
      units
      |> Enum.group_by(fn {name, _duration} -> group_fn.(name) end)
      |> Enum.flat_map(fn {_group, group_units} ->
        group_duration = group_units |> Enum.map(&elem(&1, 1)) |> Enum.sum()

        if group_duration > target do
          Enum.map(group_units, fn {name, duration} -> {[{name, duration}], duration} end)
        else
          [{group_units, group_duration}]
        end
      end)

    empty_shards = Enum.map(0..(shard_count - 1), &{&1, [], 0})

    items
    |> Enum.sort_by(&elem(&1, 1), :desc)
    |> Enum.reduce(empty_shards, fn {item_units, item_duration}, shards ->
      min_index = shards |> Enum.min_by(&elem(&1, 2)) |> elem(0)

      List.update_at(shards, min_index, fn {index, shard_units, total} ->
        {index, shard_units ++ item_units, total + item_duration}
      end)
    end)
    |> Enum.map(fn {index, shard_units, total} -> {index, Enum.sort_by(shard_units, &elem(&1, 1), :desc), total} end)
  end

  defp makespan([]), do: 0
  defp makespan(shards), do: shards |> Enum.map(&elem(&1, 2)) |> Enum.max()

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
    min_shards = Keyword.get(opts, :min) || @default_min_shards
    max_shards = Keyword.get(opts, :max) || @default_max_shards
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
