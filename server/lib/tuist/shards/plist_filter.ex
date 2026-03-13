defmodule Tuist.Shards.PlistFilter do
  @moduledoc """
  Filters `.xctestrun` plist XML to include only assigned test targets
  or inject `OnlyTestIdentifiers` for suite-level granularity.

  Works by decoding the plist XML into Elixir terms, transforming,
  and re-encoding to XML.
  """

  @xml_header ~s(<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">)

  @doc """
  Filters an xctestrun XML string based on the assigned targets and granularity.

  ## Module-level granularity
  Removes `TestTarget` dict entries from each `TestConfigurations` element
  whose `BlueprintName` is not in `assigned_targets`.

  ## Suite-level granularity
  Keeps all `TestTarget` entries but injects an `OnlyTestIdentifiers` array
  per target. `assigned_targets` should be a map of `%{blueprint_name => [class_names]}`.
  Targets not present in the map get an empty `OnlyTestIdentifiers` (no tests run).
  """
  def filter_xctestrun(xml_string, assigned_targets, granularity \\ :module)

  def filter_xctestrun(xml_string, assigned_targets, :module) when is_list(assigned_targets) do
    target_set = MapSet.new(assigned_targets)

    xml_string
    |> decode_plist()
    |> filter_module(target_set)
    |> encode_plist()
  end

  def filter_xctestrun(xml_string, assigned_targets, :suite) when is_map(assigned_targets) do
    xml_string
    |> decode_plist()
    |> inject_suite_identifiers(assigned_targets)
    |> encode_plist()
  end

  defp filter_module(plist, target_set) when is_map(plist) do
    case Map.get(plist, "TestConfigurations") do
      nil ->
        Map.new(plist, fn {k, v} -> {k, filter_module(v, target_set)} end)

      configs when is_list(configs) ->
        filtered_configs = Enum.map(configs, &filter_config_targets(&1, target_set))
        Map.put(plist, "TestConfigurations", filtered_configs)
    end
  end

  defp filter_module(value, _target_set), do: value

  defp filter_config_targets(%{"TestTargets" => targets} = cfg, target_set) when is_list(targets) do
    filtered = Enum.filter(targets, &target_in_set?(&1, target_set))
    Map.put(cfg, "TestTargets", filtered)
  end

  defp filter_config_targets(other, _target_set), do: other

  defp target_in_set?(%{"BlueprintName" => name}, target_set), do: MapSet.member?(target_set, name)
  defp target_in_set?(_target, _target_set), do: true

  defp inject_suite_identifiers(plist, assigned_targets) when is_map(plist) do
    case Map.get(plist, "TestConfigurations") do
      nil ->
        Map.new(plist, fn {k, v} -> {k, inject_suite_identifiers(v, assigned_targets)} end)

      configs when is_list(configs) ->
        updated_configs = Enum.map(configs, &inject_config_identifiers(&1, assigned_targets))
        Map.put(plist, "TestConfigurations", updated_configs)
    end
  end

  defp inject_suite_identifiers(value, _assigned_targets), do: value

  defp inject_config_identifiers(%{"TestTargets" => targets} = cfg, assigned_targets) when is_list(targets) do
    updated_targets = Enum.map(targets, &inject_target_identifiers(&1, assigned_targets))
    Map.put(cfg, "TestTargets", updated_targets)
  end

  defp inject_config_identifiers(other, _assigned_targets), do: other

  defp inject_target_identifiers(%{"BlueprintName" => name} = target, assigned_targets) do
    identifiers = Map.get(assigned_targets, name, [])

    target
    |> Map.delete("SkipTestIdentifiers")
    |> Map.put("OnlyTestIdentifiers", identifiers)
  end

  defp inject_target_identifiers(other, _assigned_targets), do: other

  # --- Plist XML decoding ---

  defp decode_plist(xml_string) do
    {doc, _} =
      xml_string
      |> String.to_charlist()
      |> :xmerl_scan.string(quiet: true)

    doc
    |> find_child_element(:plist)
    |> find_first_value_element()
    |> decode_value()
  end

  defp find_child_element({:xmlElement, name, _, _, _, _, _, _, _, _, _, _} = el, name), do: el

  defp find_child_element({:xmlElement, _, _, _, _, _, _, _, content, _, _, _}, target) do
    Enum.find_value(content, fn
      {:xmlElement, ^target, _, _, _, _, _, _, _, _, _, _} = el -> el
      {:xmlElement, _, _, _, _, _, _, _, _, _, _, _} = el -> find_child_element(el, target)
      _ -> nil
    end)
  end

  defp find_child_element(_, _), do: nil

  defp find_first_value_element({:xmlElement, _, _, _, _, _, _, _, content, _, _, _}) do
    Enum.find(content, fn
      {:xmlElement, name, _, _, _, _, _, _, _, _, _, _} ->
        name in [:dict, :array, :string, :integer, :real, true, false, :data, :date]

      _ ->
        false
    end)
  end

  defp decode_value({:xmlElement, :dict, _, _, _, _, _, _, content, _, _, _}) do
    content
    |> Enum.filter(fn
      {:xmlElement, _, _, _, _, _, _, _, _, _, _, _} -> true
      _ -> false
    end)
    |> decode_dict_pairs()
  end

  defp decode_value({:xmlElement, :array, _, _, _, _, _, _, content, _, _, _}) do
    content
    |> Enum.filter(fn
      {:xmlElement, _, _, _, _, _, _, _, _, _, _, _} -> true
      _ -> false
    end)
    |> Enum.map(&decode_value/1)
  end

  defp decode_value({:xmlElement, :string, _, _, _, _, _, _, content, _, _, _}) do
    extract_text(content)
  end

  defp decode_value({:xmlElement, :integer, _, _, _, _, _, _, content, _, _, _}) do
    content |> extract_text() |> String.to_integer()
  end

  defp decode_value({:xmlElement, :real, _, _, _, _, _, _, content, _, _, _}) do
    content |> extract_text() |> String.to_float()
  end

  defp decode_value({:xmlElement, true, _, _, _, _, _, _, _, _, _, _}), do: true
  defp decode_value({:xmlElement, false, _, _, _, _, _, _, _, _, _, _}), do: false

  defp decode_value({:xmlElement, :data, _, _, _, _, _, _, content, _, _, _}) do
    {:data, extract_text(content)}
  end

  defp decode_value({:xmlElement, :date, _, _, _, _, _, _, content, _, _, _}) do
    {:date, extract_text(content)}
  end

  defp decode_dict_pairs([]), do: %{}

  defp decode_dict_pairs([key_el | rest]) do
    case key_el do
      {:xmlElement, :key, _, _, _, _, _, _, content, _, _, _} ->
        key = extract_text(content)

        case rest do
          [value_el | remaining] ->
            value = decode_value(value_el)
            Map.put(decode_dict_pairs(remaining), key, value)

          [] ->
            %{}
        end

      _ ->
        decode_dict_pairs(rest)
    end
  end

  defp extract_text(content) do
    content
    |> Enum.filter(fn
      {:xmlText, _, _, _, _, :text} -> true
      _ -> false
    end)
    |> Enum.map_join(fn {:xmlText, _, _, _, text, :text} -> List.to_string(text) end)
    |> String.trim()
  end

  # --- Plist XML encoding ---

  defp encode_plist(value) do
    body = encode_value(value, 0)
    "#{@xml_header}\n<plist version=\"1.0\">\n#{body}\n</plist>\n"
  end

  defp encode_value(value, indent) when is_map(value) do
    pad = String.duplicate("  ", indent)
    inner_pad = String.duplicate("  ", indent + 1)

    pairs =
      value
      |> Enum.sort_by(fn {k, _} -> k end)
      |> Enum.map_join("\n", fn {k, v} ->
        "#{inner_pad}<key>#{escape_xml(k)}</key>\n#{encode_value(v, indent + 1)}"
      end)

    "#{pad}<dict>\n#{pairs}\n#{pad}</dict>"
  end

  defp encode_value(value, indent) when is_list(value) do
    pad = String.duplicate("  ", indent)

    if value == [] do
      "#{pad}<array/>"
    else
      inner =
        Enum.map_join(value, "\n", fn v -> encode_value(v, indent + 1) end)

      "#{pad}<array>\n#{inner}\n#{pad}</array>"
    end
  end

  defp encode_value(value, indent) when is_binary(value) do
    pad = String.duplicate("  ", indent)
    "#{pad}<string>#{escape_xml(value)}</string>"
  end

  defp encode_value(value, indent) when is_integer(value) do
    pad = String.duplicate("  ", indent)
    "#{pad}<integer>#{value}</integer>"
  end

  defp encode_value(value, indent) when is_float(value) do
    pad = String.duplicate("  ", indent)
    "#{pad}<real>#{value}</real>"
  end

  defp encode_value(true, indent) do
    pad = String.duplicate("  ", indent)
    "#{pad}<true/>"
  end

  defp encode_value(false, indent) do
    pad = String.duplicate("  ", indent)
    "#{pad}<false/>"
  end

  defp encode_value({:data, content}, indent) do
    pad = String.duplicate("  ", indent)
    "#{pad}<data>#{escape_xml(content)}</data>"
  end

  defp encode_value({:date, content}, indent) do
    pad = String.duplicate("  ", indent)
    "#{pad}<date>#{escape_xml(content)}</date>"
  end

  defp escape_xml(string) do
    string
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end
end
