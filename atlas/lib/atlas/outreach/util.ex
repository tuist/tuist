defmodule Atlas.Outreach.Util do
  @moduledoc """
  Shared attribute, text, and time helpers used across the outreach context.

  Keeping these in one place avoids the normalization rules drifting between
  `Atlas.Outreach` and its sibling modules.
  """

  @doc "Trims a value to a normalized string, returning nil when blank."
  def normalize_optional_text(nil), do: nil

  def normalize_optional_text(value) do
    value
    |> to_string()
    |> String.trim()
    |> case do
      "" -> nil
      normalized -> normalized
    end
  end

  @doc "True when the value is a non-blank string."
  def present?(value) when is_binary(value), do: String.trim(value) != ""
  def present?(_value), do: false

  @doc "Current UTC time truncated to the second."
  def utc_now, do: DateTime.utc_now() |> DateTime.truncate(:second)

  @doc "Fetches an attribute by its string key, falling back to the atom key."
  def attr(attrs, string_key, atom_key), do: Map.get(attrs, string_key, Map.get(attrs, atom_key))

  @doc "Converts every key in a map to a string."
  def stringify_keys(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), value} end)
  end
end
