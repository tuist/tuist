defmodule Tuist.Utilities.ByteFormatter do
  @moduledoc false

  @doc """
  Formats bytes into a human-readable string representation.

  ## Examples

      iex> ByteFormatter.format_bytes(2)
      "2 B"

      iex> ByteFormatter.format_bytes(1024)
      "1.0 KB"

      iex> ByteFormatter.format_bytes(1_000_000)
      "1.0 MB"

      iex> ByteFormatter.format_bytes(1_000_000_000)
      "1.0 GB"
  """
  def format_bytes(bytes) when is_integer(bytes) do
    cond do
      bytes >= 1_000_000_000 -> "#{Float.round(bytes / 1_000_000_000, 1)} GB"
      bytes >= 1_000_000 -> "#{Float.round(bytes / 1_000_000, 1)} MB"
      bytes >= 1_000 -> "#{Float.round(bytes / 1_000, 1)} KB"
      true -> "#{bytes} B"
    end
  end
end
