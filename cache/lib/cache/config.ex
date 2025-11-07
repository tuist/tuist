defmodule Cache.Config do
  @moduledoc false

  def float_env(name, default) when is_binary(name) do
    name
    |> System.get_env()
    |> parse_float(default)
  end

  defp parse_float(nil, default), do: default

  defp parse_float(value, default) do
    case Float.parse(value) do
      {float, _} -> float
      :error -> default
    end
  end
end
