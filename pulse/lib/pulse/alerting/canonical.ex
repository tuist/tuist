defmodule Pulse.Alerting.Canonical do
  @moduledoc false

  # A deterministic JSON representation, without converting user keys to atoms.
  def encode(value) when is_map(value) do
    fields =
      value
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map(fn {key, item} when is_binary(key) -> [Pulse.JSON.encode!(key), ":", encode(item)] end)
      |> Enum.intersperse(",")

    IO.iodata_to_binary(["{", fields, "}"])
  end

  def encode(value) when is_list(value),
    do: IO.iodata_to_binary(["[", value |> Enum.map(&encode/1) |> Enum.intersperse(","), "]"])

  def encode(value), do: Pulse.JSON.encode!(value)
  def digest(bytes), do: :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)
  def hash(value), do: value |> encode() |> digest()
end
