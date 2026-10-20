defmodule Atlas.Accounts.Lifecycle do
  @moduledoc false

  @definitions %{
    "customer" => %{label: "Customer", color: "success", order: 10},
    "prospect" => %{label: "Prospect", color: "attention", order: 20},
    "lead" => %{label: "Lead", color: "warning", order: 30},
    "unknown" => %{label: "Unknown", color: "neutral", order: 999}
  }

  def from_segment(segment) do
    key = key(segment)
    Map.put(@definitions[key] || @definitions["unknown"], :key, key)
  end

  def key(segment) do
    case segment do
      :customer -> "customer"
      :prospect -> "prospect"
      :lead -> "lead"
      "customer" -> "customer"
      "prospect" -> "prospect"
      "lead" -> "lead"
      _other -> "unknown"
    end
  end

  def label(segment), do: from_segment(segment).label

  def color(segment), do: from_segment(segment).color

  def sort_order(key) do
    @definitions
    |> Map.get(key, %{order: 500})
    |> Map.fetch!(:order)
  end
end
