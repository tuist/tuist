defmodule Pulse.Alerting.Lifecycle do
  @moduledoc "Pure native threshold lifecycle. Timers are absolute and advance only on successful evaluations."
  alias Pulse.Alerting.{Canonical, Rule}

  @max_instances 128

  def step(rule, previous, samples, timestamp) do
    with true <- is_list(samples) and length(samples) <= @max_instances,
         {:ok, points} <- points(samples, rule) do
      transition(rule, previous, points, timestamp)
    else
      _ -> {:error, :invalid_evaluation}
    end
  end

  defp transition(rule, previous, points, timestamp) do
    health = if map_size(points) == 0, do: "no_data", else: "ok"

    if health == "no_data" and Map.get(rule, "no_data_policy", "keep_last") == "keep_last" do
      {:ok, previous, [], health}
    else
      transition_instances(rule, previous, points, timestamp, health)
    end
  end

  defp transition_instances(rule, previous, points, timestamp, health) do
    keys = (Map.keys(previous) ++ Map.keys(points)) |> Enum.uniq() |> Enum.sort()
    {instances, events} = Enum.reduce(keys, {%{}, []}, &step_instance(&1, &2, previous, points, rule, timestamp))
    if map_size(instances) <= @max_instances, do: {:ok, instances, events, health}, else: {:error, :instance_limit}
  end

  defp step_instance(key, {acc, events}, previous, points, rule, timestamp) do
    point = points[key]
    hit = point && compare(point["number"], rule["threshold"])
    {next, event} = advance(previous[key], point, hit == true, rule, timestamp)
    acc = if next, do: Map.put(acc, key, next), else: acc
    {acc, if(event, do: events ++ [event], else: events)}
  end

  defp points(samples, rule), do: Enum.reduce_while(samples, {:ok, %{}}, &point(&1, &2, rule))

  defp point(sample, {:ok, acc}, rule) do
    with %{"metric" => labels, "value" => [_time, value]} <- sample,
         true <- Rule.labels?(labels) and is_binary(value),
         {number, ""} <- Float.parse(value),
         labels = labels |> Map.delete("__name__") |> Map.merge(rule["labels"]) |> Map.put("alertname", rule["name"]),
         true <- Rule.labels?(labels),
         labels = Map.new(labels, fn {key, item} -> {:binary.copy(key), :binary.copy(item)} end),
         key = Canonical.encode(labels),
         false <- Map.has_key?(acc, key) do
      {:cont, {:ok, Map.put(acc, key, %{"labels" => labels, "value" => value, "number" => number})}}
    else
      _ -> {:halt, {:error, :invalid_samples}}
    end
  end

  defp advance(nil, _point, false, _rule, _time), do: {nil, nil}

  defp advance(nil, point, true, rule, time) do
    status = if rule["for_ms"] == 0, do: "firing", else: "pending"

    next = %{
      "labels" => point["labels"],
      "value" => point["value"],
      "status" => status,
      "pending_since_ns" => Integer.to_string(time),
      "firing_since_ns" => if(status == "firing", do: Integer.to_string(time)),
      "hold_until_ns" => nil
    }

    {next, event(status, next, time)}
  end

  defp advance(prior, point, true, rule, time) do
    next = Map.put(prior, "value", point["value"])

    cond do
      prior["status"] == "pending" and time - String.to_integer(prior["pending_since_ns"]) >= rule["for_ms"] * 1_000_000 ->
        next = Map.merge(next, %{"status" => "firing", "firing_since_ns" => Integer.to_string(time)})
        {next, event("firing", next, time)}

      prior["status"] == "recovering" ->
        next = Map.merge(next, %{"status" => "firing", "hold_until_ns" => nil})
        {next, event("retriggered", next, time)}

      true ->
        {next, nil}
    end
  end

  defp advance(prior, point, false, rule, time) do
    prior = if point, do: Map.put(prior, "value", point["value"]), else: prior

    cond do
      prior["status"] == "pending" ->
        {nil, event("resolved", prior, time)}

      prior["status"] == "firing" and rule["keep_firing_ms"] > 0 ->
        next =
          Map.merge(prior, %{
            "status" => "recovering",
            "hold_until_ns" => Integer.to_string(time + rule["keep_firing_ms"] * 1_000_000)
          })

        {next, event("recovering", next, time)}

      prior["status"] == "recovering" and time < String.to_integer(prior["hold_until_ns"]) ->
        {prior, nil}

      true ->
        {nil, event("resolved", prior, time)}
    end
  end

  defp event(type, instance, time),
    do: %{
      "type" => type,
      "instance" => instance,
      "timestamp_ns" => Integer.to_string(time),
      "provenance" => %{"labels" => "untrusted_metric_values"}
    }

  defp compare(value, %{"op" => "gt", "value" => threshold}), do: value > threshold
  defp compare(value, %{"op" => "lt", "value" => threshold}), do: value < threshold
  defp compare(value, %{"op" => "eq", "value" => threshold}), do: value == threshold
end
