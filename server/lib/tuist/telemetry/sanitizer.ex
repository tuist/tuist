defmodule Tuist.Telemetry.Sanitizer do
  @moduledoc """
  A telemetry handler that sanitizes metadata values before they reach
  PromEx/Peep to avoid String.Chars protocol errors for unsupported types.
  """

  @doc """
  Sanitizes a telemetry metadata map by converting all values to
  types that are supported by String.Chars protocol.
  """
  def sanitize_metadata(metadata) when is_map(metadata) do
    Map.new(metadata, fn {key, value} -> {key, sanitize_value(value)} end)
  end

  def sanitize_metadata(metadata), do: metadata

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
    case value do
      %{__struct__: module} ->
        "#{inspect(module)}"

      _ ->
        inspect(value)
    end
  end

  def sanitize_value(value) do
    to_string(value)
  rescue
    Protocol.UndefinedError ->
      inspect(value)

    _ ->
      inspect(value)
  end
end
