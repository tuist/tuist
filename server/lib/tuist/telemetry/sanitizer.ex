defmodule Tuist.Telemetry.Sanitizer do
  @moduledoc """
  A telemetry handler that sanitizes metadata values before they reach
  PromEx/Peep to avoid String.Chars protocol errors for unsupported types.
  """

  @doc """
  Sanitizes a single value to ensure it's compatible with String.Chars protocol.
  """
  def sanitize_value(value) when is_binary(value), do: value
  def sanitize_value(value) when is_atom(value), do: value
  def sanitize_value(value) when is_integer(value), do: value
  def sanitize_value(value) when is_float(value), do: value
  def sanitize_value(value) when is_boolean(value), do: value

  def sanitize_value(value) when is_list(value) do
    # For simplicity and safety, always inspect lists
    inspect(value)
  end

  def sanitize_value(value) when is_struct(value) do
    %{__struct__: module} = value
    "#{inspect(module)}"
  end

  def sanitize_value(value) do
    inspect(value)
  end
end
