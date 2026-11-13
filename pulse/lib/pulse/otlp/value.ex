defmodule Pulse.OTLP.Value do
  @moduledoc "OTLP AnyValue normalization with a lossless typed representation alongside query-friendly values."

  @fields ~w(stringValue boolValue intValue doubleValue bytesValue arrayValue kvlistValue)
  @min_int -9_223_372_036_854_775_808
  @max_int 9_223_372_036_854_775_807

  def decode(value) when is_map(value) do
    Map.take(value, @fields)
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> case do
      [] -> {:ok, nil, %{}}
      [{key, item}] -> member(key, item)
      _ -> :error
    end
  end

  def decode(nil), do: {:ok, nil, %{}}
  def decode(_), do: :error

  def attributes(owner) when is_map(owner) do
    case field(owner, "attributes", []) do
      pairs when is_list(pairs) -> pairs(pairs)
      _ -> :error
    end
  end

  def attributes(_), do: :error

  defp pairs(pairs) when is_list(pairs) do
    Enum.reduce_while(pairs, {:ok, %{}, []}, &pair/2)
    |> case do
      {:ok, values, typed} -> {:ok, values, Enum.reverse(typed)}
      _ -> :error
    end
  end

  defp pairs(_), do: :error

  defp pair(%{"key" => key} = pair, {:ok, values, typed}) when is_binary(key) and byte_size(key) > 0 do
    with false <- Map.has_key?(values, key),
         {:ok, value, raw} <- decode(Map.get(pair, "value", %{})) do
      key = Pulse.JSON.detach(key)
      {:cont, {:ok, Map.put(values, key, value), [%{"key" => key, "value" => raw} | typed]}}
    else
      _ -> {:halt, :error}
    end
  end

  defp pair(_, _), do: {:halt, :error}

  defp member("stringValue" = key, value) when is_binary(value) do
    value = Pulse.JSON.detach(value)
    {:ok, value, %{key => value}}
  end

  defp member("boolValue" = key, value) when is_boolean(value), do: {:ok, value, %{key => value}}

  defp member("intValue" = key, value) do
    case integer(value, @min_int, @max_int) do
      {:ok, value} -> {:ok, value, %{key => Integer.to_string(value)}}
      _ -> :error
    end
  end

  defp member("doubleValue" = key, value) when is_number(value) do
    double = value / 1
    {:ok, double, %{key => double}}
  rescue
    ArithmeticError -> :error
  end

  # BEAM floats cannot represent non-finite doubles. The typed envelope keeps
  # their IEEE meaning; the query-friendly projection uses their JSON spelling.
  defp member("doubleValue" = key, value) when value in ["NaN", "Infinity", "-Infinity"],
    do: {:ok, value, %{key => value}}

  # Bound numeric conversion independently of ordinary message string size.
  defp member("doubleValue" = key, value) when is_binary(value) and byte_size(value) <= 1024 do
    case Float.parse(value) do
      {double, ""} -> {:ok, double, %{key => double}}
      _ -> :error
    end
  rescue
    _ in [ArgumentError, ArithmeticError] -> :error
  end

  defp member("bytesValue" = key, value) when is_binary(value) do
    decoded =
      case Base.decode64(value, padding: false) do
        {:ok, _} = ok -> ok
        _ -> Base.url_decode64(value, padding: false)
      end

    case decoded do
      {:ok, bytes} ->
        base64 = Base.encode64(bytes)
        {:ok, base64, %{key => base64}}

      _ ->
        :error
    end
  end

  defp member("arrayValue" = key, owner) when is_map(owner) do
    case field(owner, "values", []) do
      values when is_list(values) -> array(key, values)
      _ -> :error
    end
  end

  defp member("kvlistValue" = key, owner) when is_map(owner) do
    with {:ok, values, typed} <- pairs(field(owner, "values", [])),
         do: {:ok, values, %{key => %{"values" => typed}}}
  end

  defp member(_, _), do: :error

  defp array(key, items) do
    Enum.reduce_while(items, {:ok, [], []}, &array_item/2)
    |> case do
      {:ok, values, typed} -> {:ok, Enum.reverse(values), %{key => %{"values" => Enum.reverse(typed)}}}
      _ -> :error
    end
  end

  defp array_item(nil, _), do: {:halt, :error}

  defp array_item(item, {:ok, values, typed}) do
    case decode(item) do
      {:ok, value, raw} -> {:cont, {:ok, [value | values], [raw | typed]}}
      _ -> {:halt, :error}
    end
  end

  def field(owner, key, default) do
    case Map.get(owner, key) do
      nil -> default
      value -> value
    end
  end

  # Already-decoded maps may contain float zero. It still means integer zero;
  # raw OTLP decoding handles integral lexemes before float conversion, while
  # doubleValue retains its sign.
  def integer(value, low, high) when is_float(value) and value == 0.0 and low <= 0 and high >= 0, do: {:ok, 0}
  def integer(value, low, high) when is_integer(value) and value >= low and value <= high, do: {:ok, value}

  def integer(value, low, high) when is_binary(value) do
    case Pulse.OTLP.Integer.parse(value) do
      {:ok, integer} -> integer(integer, low, high)
      :error -> :error
    end
  end

  def integer(_, _, _), do: :error
end
