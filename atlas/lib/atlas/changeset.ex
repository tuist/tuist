defmodule Atlas.Changeset do
  @moduledoc """
  Shared `Ecto.Changeset` helpers.
  """

  import Ecto.Changeset

  @doc """
  Trims the given string fields, converting blank strings to `nil` and leaving
  non-string values untouched.
  """
  def normalize_string_fields(changeset, fields) do
    Enum.reduce(fields, changeset, &normalize_string_field/2)
  end

  defp normalize_string_field(field, changeset) do
    update_change(changeset, field, fn
      nil ->
        nil

      value when is_binary(value) ->
        case String.trim(value) do
          "" -> nil
          normalized -> normalized
        end

      value ->
        value
    end)
  end
end
