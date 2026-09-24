defmodule Atlas.Accounts.DealStage do
  @moduledoc false

  @definitions %{
    "discovery" => %{label: "Discovery", color: "neutral", order: 10, attention: false},
    "poc" => %{label: "POC", color: "attention", order: 20, attention: false},
    "legal_review" => %{label: "Legal Review", color: "warning", order: 30, attention: true},
    "security_review" => %{label: "Security Review", color: "warning", order: 40, attention: true},
    "negotiation" => %{label: "Negotiation", color: "attention", order: 50, attention: false},
    "closed_won" => %{label: "Closed Won", color: "success", order: 60, attention: false},
    "closed_lost" => %{label: "Closed Lost", color: "neutral", order: 70, attention: false}
  }

  def keys, do: Map.keys(@definitions)

  def from_key(key) do
    case Map.fetch(@definitions, to_string(key)) do
      {:ok, definition} -> Map.put(definition, :key, to_string(key))
      :error -> nil
    end
  end

  def label(key) do
    case from_key(key) do
      nil -> nil
      definition -> definition.label
    end
  end

  def color(key) do
    case from_key(key) do
      nil -> "neutral"
      definition -> definition.color
    end
  end

  def attention?(key) do
    case from_key(key) do
      nil -> false
      definition -> definition.attention
    end
  end

  def attention_keys do
    @definitions
    |> Enum.filter(fn {_key, definition} -> definition.attention end)
    |> Enum.map(fn {key, _definition} -> key end)
  end

  def sort_order(key) do
    @definitions
    |> Map.get(to_string(key), %{order: 999})
    |> Map.fetch!(:order)
  end

  def all do
    @definitions
    |> Enum.map(fn {key, definition} -> Map.put(definition, :key, key) end)
    |> Enum.sort_by(& &1.order)
  end
end
