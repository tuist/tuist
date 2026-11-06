defmodule Pulse.PromQL.LabelReplace do
  @moduledoc false
  alias Pulse.Codec.NIF
  alias Pulse.PromQL.Evaluator

  def run(vector, [{:string, dst}, {:string, replacement}, {:string, src}, {:string, pattern}]) do
    {:ok, regex} = NIF.compile_metric_capture_regex(pattern)

    Enum.map(vector, fn {labels, samples} ->
      Evaluator.charge(:work, 1)
      {replace(labels, regex, dst, replacement, src), samples}
    end)
  end

  defp replace(labels, regex, dst, replacement, src) do
    case NIF.metric_regex_captures(regex, Map.get(labels, src, "")) do
      nil -> labels
      captures -> set_label(labels, dst, expand(replacement, captures))
    end
  end

  defp set_label(labels, name, ""), do: Map.delete(labels, name)
  defp set_label(labels, name, value), do: Map.put(labels, name, value)

  defp expand(text, captures) do
    Regex.replace(~r/\$\$|\$\{([\p{L}\p{Nd}_]+)\}|\$([\p{L}\p{Nd}_]+)/u, text, fn whole, braced, bare ->
      capture(whole, braced, bare, captures)
    end)
  end

  defp capture("$$", _, _, _), do: "$"
  defp capture(_, "", bare, captures), do: Map.get(captures, bare, "")
  defp capture(_, braced, _, captures), do: Map.get(captures, braced, "")
end
