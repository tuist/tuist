defmodule Tuist.Bazel.RemoteExecutionProfile do
  @moduledoc "Associates reported server phases with unambiguous same-thread action intervals."

  @phases %{
    {"Remote execution queuing time", "queue"} => :remote_queue_ms,
    {"Remote execution file fetching", "fetch"} => :remote_input_fetch_ms,
    {"Remote execution process wall time", "execute"} => :remote_execution_ms,
    {"Remote execution upload time", "upload"} => :remote_output_upload_ms
  }

  def fields, do: ~w(remote_queue_ms remote_input_fetch_ms remote_execution_ms remote_output_upload_ms)a

  def associate(events) do
    events
    |> Enum.with_index()
    |> Enum.reduce(%{}, fn {event, index}, lanes ->
      case interval(event, index) do
        nil -> lanes
        {lane, interval} -> Map.update(lanes, lane, [interval], &[interval | &1])
      end
    end)
    |> Enum.reduce(%{}, fn {_lane, intervals}, result ->
      intervals
      |> Enum.sort_by(fn {start, kind, _, _} -> {start, kind} end)
      |> Enum.reduce({:gb_trees.empty(), result}, &associate_interval/2)
      |> elem(1)
    end)
  end

  defp interval(%{"ph" => "X", "ts" => start, "dur" => duration, "pid" => pid, "tid" => tid} = event, index)
       when is_number(start) and start >= 0 and is_number(duration) and duration >= 0 and is_integer(pid) and
              is_integer(tid) do
    cond do
      event["cat"] == "action processing" -> {{pid, tid}, {start, 0, start + duration, index}}
      field = @phases[{event["cat"], event["name"]}] -> {{pid, tid}, {start, 1, start + duration, field}}
      true -> nil
    end
  end

  defp interval(_, _), do: nil

  defp associate_interval({start, kind, finish, id}, {active, result}) do
    active = expire(active, start)

    cond do
      kind == 0 ->
        {:gb_trees.insert({finish, id}, id, active), result}

      :gb_trees.size(active) == 1 ->
        {{action_finish, index}, _} = :gb_trees.smallest(active)

        if finish <= action_finish do
          phases = Map.update(Map.get(result, index, %{}), id, (finish - start) / 1000, &(&1 + (finish - start) / 1000))
          {active, Map.put(result, index, phases)}
        else
          {active, result}
        end

      true ->
        {active, result}
    end
  end

  # A tree keeps adversarial overlapping profiles bounded to O(n log n), rather
  # than scanning every active action for every phase. Ambiguity stays unknown.
  defp expire(active, start) do
    if :gb_trees.is_empty(active) do
      active
    else
      {{finish, _}, _} = :gb_trees.smallest(active)
      if finish <= start, do: active |> :gb_trees.take_smallest() |> elem(2) |> expire(start), else: active
    end
  end
end
