defmodule Atlas.Agents.IdentityNormalization do
  @moduledoc false

  def normalize_key(value) when is_binary(value), do: value |> String.trim() |> String.downcase()
  def normalize_key(value), do: value

  def normalize_bindings(bindings) when is_map(bindings), do: normalize_binding_value(bindings)
  def normalize_bindings(_bindings), do: %{}

  def normalize_tool_groups(groups) when is_list(groups) do
    groups
    |> Enum.map(&normalize_string/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&String.downcase/1)
    |> Enum.uniq()
  end

  def normalize_tool_groups(_groups), do: []

  def normalize_agent_tool_groups(groups, known_agents \\ nil)
  def normalize_agent_tool_groups(groups, _known_agents) when is_map(groups) and map_size(groups) == 0, do: %{}

  def normalize_agent_tool_groups(groups, known_agents) when is_map(groups) and is_list(known_agents) do
    Map.new(known_agents, fn agent ->
      key = Atom.to_string(agent)
      {key, groups |> map_get(key) |> normalize_tool_groups()}
    end)
  end

  def normalize_agent_tool_groups(groups, _known_agents) when is_map(groups) do
    Map.new(groups, fn {key, groups} ->
      {to_string(key), normalize_tool_groups(groups)}
    end)
  end

  def normalize_agent_tool_groups(groups, known_agents) when is_list(groups) do
    groups
    |> Map.new()
    |> normalize_agent_tool_groups(known_agents)
  end

  def normalize_agent_tool_groups(_groups, _known_agents), do: %{}

  def normalize_requester_rules(rules) when is_map(rules) do
    rules
    |> Enum.reduce(%{}, fn {key, value}, acc ->
      with normalized_key when not is_nil(normalized_key) <- normalize_string(key),
           normalized_value when not is_nil(normalized_value) <- normalize_string(value) do
        Map.put(acc, String.downcase(normalized_key), String.downcase(normalized_value))
      else
        _ -> acc
      end
    end)
  end

  def normalize_requester_rules(_rules), do: %{}

  def normalize_string(nil), do: nil
  def normalize_string(value) when is_atom(value), do: value |> Atom.to_string() |> normalize_string()

  def normalize_string(value) when is_binary(value) do
    value
    |> String.trim()
    |> case do
      "" -> nil
      trimmed -> trimmed
    end
  end

  def normalize_string(_value), do: nil

  defp normalize_binding_value(value) when is_map(value) do
    Map.new(value, fn {key, value} ->
      {normalize_binding_key(key), normalize_binding_value(value)}
    end)
  end

  defp normalize_binding_value(value) when is_list(value), do: Enum.map(value, &normalize_binding_value/1)
  defp normalize_binding_value(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_binding_value(value), do: value

  defp normalize_binding_key(key) when is_atom(key), do: Atom.to_string(key)
  defp normalize_binding_key(key), do: to_string(key)

  defp map_get(map, "conversation") when is_map(map), do: Map.get(map, "conversation") || Map.get(map, :conversation)

  defp map_get(map, "systems_investigator") when is_map(map) do
    Map.get(map, "systems_investigator") || Map.get(map, :systems_investigator)
  end
end
