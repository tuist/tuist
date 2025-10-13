defmodule TuistWeb.Utilities.FormatHelpers do
  @moduledoc """
  Utility functions for formatting values in views.
  """

  use Gettext, backend: TuistWeb.Gettext

  @doc """
  Returns "Unknown" for nil or empty string values, otherwise returns the value.
  """
  def value_or_unknown(value) when value in [nil, ""], do: gettext("Unknown")
  def value_or_unknown(value) when is_binary(value), do: value
  def value_or_unknown(value), do: to_string(value)

  @doc """
  Returns "None" for nil or empty string values, otherwise returns the value.
  """
  def value_or_none(value) when value in [nil, ""], do: gettext("None")
  def value_or_none(value) when is_binary(value), do: value
  def value_or_none(value), do: to_string(value)
end
