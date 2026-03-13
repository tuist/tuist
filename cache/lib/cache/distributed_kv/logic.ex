defmodule Cache.DistributedKV.Logic do
  @moduledoc false

  def compare_source_versions(nil, _left_node, nil, _right_node), do: :eq
  def compare_source_versions(nil, _left_node, _right_time, _right_node), do: :lt
  def compare_source_versions(_left_time, _left_node, nil, _right_node), do: :gt

  def compare_source_versions(left_time, left_node, right_time, right_node) do
    case DateTime.compare(left_time, right_time) do
      :eq -> compare_strings(left_node || "", right_node || "")
      other -> other
    end
  end

  def max_datetime(nil, right), do: right
  def max_datetime(left, nil), do: left
  def max_datetime(left, right), do: if(DateTime.before?(left, right), do: right, else: left)

  def compare_strings(left, right) do
    cond do
      left > right -> :gt
      left < right -> :lt
      true -> :eq
    end
  end
end
