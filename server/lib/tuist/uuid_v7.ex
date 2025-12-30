defmodule Tuist.UUIDv7 do
  @moduledoc ~S"""
  A module that provides function to interact with the UUIDv7 unique identifiers.
  """

  def valid?(uuid) do
    case UUIDv7.cast(uuid) do
      {:ok, _} -> true
      :error -> false
    end
  end

  def to_int64(uuid) do
    case UUIDv7.cast(uuid) do
      {:ok, uuid} ->
        uuid
        |> String.replace("-", "")
        |> Base.decode16!(case: :lower)
        |> then(fn
          <<timestamp_ms::48, _version::4, random_a::12, _variant::2, random_b::62>> ->
            # We're taking the fully 48 bits of the timestamp, and then 16 random bits.
            # This means we have 16 bits of entropy per _millisecond_ of UUID generation. Should be more than enough to avoid collisions at our scale - won't last forever, but we'll have deprecated `legacy_id` fully by the time it becomes a thing.
            <<int64::64>> = <<timestamp_ms::48, random_a::12, random_b::4>>
            int64
        end)

      :error ->
        nil
    end
  end
end
