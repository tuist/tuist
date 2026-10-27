defmodule Atlas.Finance.Providers.Helpers do
  @moduledoc false

  def datetime(nil), do: nil

  def datetime(%DateTime{} = datetime), do: DateTime.truncate(datetime, :second)

  def datetime(%NaiveDateTime{} = datetime) do
    datetime
    |> DateTime.from_naive!("Etc/UTC")
    |> DateTime.truncate(:second)
  end

  def datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} ->
        DateTime.truncate(datetime, :second)

      _error ->
        case NaiveDateTime.from_iso8601(value) do
          {:ok, datetime} -> datetime(datetime)
          _error -> nil
        end
    end
  end

  def datetime(_value), do: nil

  def decimal(nil), do: nil
  def decimal(%Decimal{} = decimal), do: decimal
  def decimal(value) when is_integer(value), do: Decimal.new(value)
  def decimal(value) when is_float(value), do: Decimal.from_float(value)

  def decimal(value) when is_binary(value) do
    case Decimal.parse(String.trim(value)) do
      {decimal, ""} -> decimal
      _error -> nil
    end
  end

  def decimal(_value), do: nil

  def presence(nil), do: nil

  def presence(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  def presence(value), do: value

  def compact_map(map) when is_map(map) do
    map
    |> Enum.reject(fn
      {_key, nil} -> true
      {_key, ""} -> true
      {_key, []} -> true
      {_key, %{} = nested} -> map_size(nested) == 0
      _entry -> false
    end)
    |> Map.new()
  end

  def compact_map(_other), do: %{}

  def stable_hash(term) do
    term
    |> JSON.encode!()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  def max_datetime(nil, datetime), do: datetime
  def max_datetime(datetime, nil), do: datetime

  def max_datetime(%DateTime{} = left, %DateTime{} = right) do
    if DateTime.after?(left, right), do: left, else: right
  end
end
