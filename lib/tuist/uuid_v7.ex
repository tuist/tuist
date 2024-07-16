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
end
