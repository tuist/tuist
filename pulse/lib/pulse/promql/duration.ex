defmodule Pulse.PromQL.Duration do
  @moduledoc false
  alias Pulse.PromQL.FloatParser
  alias Pulse.PromQL.Number
  alias Pulse.PromQL.Time

  @max_ns 31_536_000_000_000_000

  # Resolve against the requested outer query once, before any storage reads.
  # Subqueries must not reinterpret step()/range() using their own grids.
  def resolve(expression, context) do
    {expression, work} = walk(expression, context, 0)
    {:ok, expression, work}
  catch
    :invalid_duration -> {:error, :invalid_duration}
  end

  defp walk({:duration, expr}, context, work) do
    {seconds, work} = value(expr, context, work)

    if not is_number(seconds) or abs(seconds) > @max_ns / 1_000_000_000,
      do: throw(:invalid_duration)

    {round(seconds * 1_000_000_000), work}
  end

  # Mimir's default is one minute, independent of the outer step and window.
  defp walk({:subquery, inner, window, nil, offset}, context, work),
    do: walk({:subquery, inner, window, 60_000_000_000, offset}, context, work)

  defp walk(tuple, context, work) when is_tuple(tuple) do
    {items, work} = tuple |> Tuple.to_list() |> walk(context, work)
    result = List.to_tuple(items)

    case result do
      {:range, _, window, _} ->
        positive!(window)

      {:subquery, _, window, step, _} ->
        positive!(window)
        positive!(step)

      _ ->
        :ok
    end

    {result, work}
  end

  defp walk(items, context, work) when is_list(items), do: Enum.map_reduce(items, work, &walk(&1, context, &2))

  defp walk(value, _context, work), do: {value, work}

  defp positive!(ns) do
    if ns <= 0 or ns > @max_ns, do: throw(:invalid_duration)
  end

  defp value({:duration_literal, ns}, _context, work), do: {Time.seconds(ns), work + 1}

  defp value({:duration_number, text}, _context, work) do
    {:ok, number} = FloatParser.parse(text, :literal)
    {number, work + 1}
  end

  defp value({:call, name, []}, context, work), do: {Map.fetch!(context, name), work + 1}

  defp value({:call, name, [left, right]}, context, work) do
    {left, work} = value(left, context, work)
    {right, work} = value(right, context, work)
    {Number.extremum(name, left, right), work + 1}
  end

  defp value({:unary, "-", inner}, context, work) do
    {inner, work} = value(inner, context, work)
    {Number.negate(inner), work + 1}
  end

  defp value({:binary, op, [], left, right}, context, work) do
    {left, work} = value(left, context, work)
    {right, work} = value(right, context, work)
    if op in ["/", "%"] and right == 0, do: throw(:invalid_duration)
    {Number.binary(op, left, right), work + 1}
  end
end
