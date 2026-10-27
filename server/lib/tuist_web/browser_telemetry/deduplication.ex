defmodule TuistWeb.BrowserTelemetry.Deduplication do
  @moduledoc """
  Marks acknowledged LCP replays without discarding the original observations.
  The identity excludes collector context, which changes on each delivery.
  """

  alias Tuist.BrowserTelemetry.Receipts

  def deliver(payload, forward) do
    measurements = Enum.map(payload["measurements"], &{&1, key(&1, payload["meta"])})
    keys = for {_, key} <- measurements, not is_nil(key), do: key

    Receipts.deliver(keys, fn duplicates ->
      {measurements, _seen} =
        Enum.map_reduce(measurements, duplicates, fn {measurement, key}, seen ->
          status =
            cond do
              is_nil(key) -> "untracked"
              MapSet.member?(seen, key) -> "duplicate"
              true -> "unique"
            end

          measurement = put_in(measurement, ["context", "rum_deduplication"], status)
          {measurement, if(is_nil(key), do: seen, else: MapSet.put(seen, key))}
        end)

      forward.(Map.put(payload, "measurements", measurements))
    end)
  end

  def key(%{"type" => "web-vitals", "values" => %{"lcp" => lcp}, "context" => context}, %{"session" => %{"id" => session}})
      when is_number(lcp) and lcp >= 0 and is_map(context) do
    navigation = context["navigation_entry_id"]
    id = context["id"]

    if Enum.all?([session, navigation, id], &identifier?/1) do
      # Keep revised values distinct, including bfcache/visibility updates.
      # No URL, credential, session ID or payload is persisted in the receipt.
      value = if is_float(lcp) and lcp == trunc(lcp), do: trunc(lcp), else: lcp
      :crypto.hash(:sha256, :erlang.term_to_binary({session, navigation, id, value}))
    end
  end

  def key(_, _), do: nil

  defp identifier?(value),
    do: is_binary(value) and byte_size(value) in 1..256 and String.trim(value) not in ["", "unknown"]
end
