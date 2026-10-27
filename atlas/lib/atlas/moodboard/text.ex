defmodule Atlas.Moodboard.Text do
  @moduledoc false

  def clean(value, limit) when is_binary(value) do
    if String.valid?(value) do
      value |> String.replace(~r/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/u, "") |> String.slice(0, limit)
    end
  end

  def clean(_value, _limit), do: nil

  def valid?(value), do: String.valid?(value) and not String.contains?(value, <<0>>)
end
