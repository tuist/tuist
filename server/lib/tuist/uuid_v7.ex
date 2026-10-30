defmodule Tuist.UUIDv7 do
  @moduledoc ~S"""
  A module that provides function to interact with the UUIDv7 unique identifiers.
  """

  def deterministic(%NaiveDateTime{} = timestamp, identity) do
    milliseconds = NaiveDateTime.diff(timestamp, ~N[1970-01-01 00:00:00], :millisecond)
    payload = :erlang.term_to_binary(identity, [:deterministic])
    <<random_a::12, random_b::62, _::bitstring>> = :crypto.hash(:sha256, payload)
    Ecto.UUID.cast!(<<milliseconds::48, 7::4, random_a::12, 2::2, random_b::62>>)
  end

  def valid?(uuid) do
    case UUIDv7.cast(uuid) do
      {:ok, _} -> true
      :error -> false
    end
  end
end
