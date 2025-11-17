defmodule Tuist.Utilities.ThroughputFormatter do
  @moduledoc false

  @doc """
  Formats throughput (bytes per second) into a human-readable Mbps string representation.

  ## Examples

      iex> ThroughputFormatter.format_throughput(125_000)
      "1.0 Mbps"

      iex> ThroughputFormatter.format_throughput(1_250_000)
      "10.0 Mbps"

      iex> ThroughputFormatter.format_throughput(12_500_000)
      "100.0 Mbps"
  """
  def format_throughput(bytes_per_second) when is_number(bytes_per_second) do
    # Convert bytes/s to Mbps: bytes * 8 bits/byte / 1,000,000 bits/Mb
    mbps = bytes_per_second * 8 / 1_000_000
    # Use :erlang.float_to_binary to avoid scientific notation for large values
    formatted = :erlang.float_to_binary(mbps, decimals: 1)
    "#{formatted} Mbps"
  end
end
