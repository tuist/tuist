defmodule Pulse.Test.TempoSearchOracle do
  @moduledoc false

  # Protobuf JSON may spell doubleValue as an integral JSON number, including
  # -0. Sorting removes only attribute map iteration, never sample/trace order.
  def normalize(%{"doubleValue" => value}) when value == 0, do: %{"doubleValue" => 0.0}
  def normalize(%{"doubleValue" => value}) when is_number(value), do: %{"doubleValue" => value / 1}

  def normalize(map) when is_map(map) do
    Map.new(map, fn
      {"attributes", values} -> {"attributes", values |> Enum.map(&normalize/1) |> Enum.sort()}
      {key, value} -> {key, normalize(value)}
    end)
  end

  def normalize(list) when is_list(list), do: Enum.map(list, &normalize/1)
  def normalize(value), do: value

  def response(body), do: body |> Map.put_new("traces", []) |> normalize()
end
