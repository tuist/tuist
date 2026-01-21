defmodule TuistCommon.BodyReader do
  @moduledoc """
  Shared utilities for reading request bodies with dynamic timeouts.

  This module provides functions to calculate appropriate read timeouts based on
  the expected content length, allowing slower connections to complete uploads
  while still timing out stalled transfers.
  """

  @default_read_timeout 60_000
  @default_read_length 262_144
  @default_min_throughput_bytes_per_sec 50 * 1024

  @doc """
  Calculates a dynamic read timeout based on content length.

  The timeout is calculated to allow a minimum throughput rate, with a floor
  to prevent extremely short timeouts for small uploads.

  ## Options

    * `:min_timeout` - Minimum timeout in milliseconds (default: 60_000)
    * `:min_throughput` - Minimum expected throughput in bytes/second (default: 51_200 = 50KB/s)

  ## Examples

      iex> TuistCommon.BodyReader.calculate_timeout(1_000_000)
      60_000

      iex> TuistCommon.BodyReader.calculate_timeout(25_000_000)
      500_000

  """
  @spec calculate_timeout(non_neg_integer(), keyword()) :: non_neg_integer()
  def calculate_timeout(content_length, opts \\ []) do
    min_timeout = Keyword.get(opts, :min_timeout, @default_read_timeout)
    min_throughput = Keyword.get(opts, :min_throughput, @default_min_throughput_bytes_per_sec)

    calculated_timeout = div(content_length * 1000, min_throughput)
    max(min_timeout, calculated_timeout)
  end

  @doc """
  Returns read options with a dynamic timeout based on the request's Content-Length.

  If no Content-Length header is present, returns the default options.

  ## Options

    * `:length` - Maximum bytes to read total (default: from base_opts or 8MB)
    * `:read_length` - Bytes to read per chunk (default: 262_144 = 256KB)
    * `:read_timeout` - Base timeout, will be overridden by dynamic calculation
    * `:min_timeout` - Minimum timeout in milliseconds (default: 60_000)
    * `:min_throughput` - Minimum expected throughput in bytes/second (default: 51_200)

  ## Examples

      conn = %Plug.Conn{req_headers: [{"content-length", "10000000"}]}
      opts = TuistCommon.BodyReader.read_opts(conn)
      # Returns opts with ~200s timeout for 10MB at 50KB/s

  """
  @spec read_opts(Plug.Conn.t(), keyword()) :: keyword()
  def read_opts(conn, base_opts \\ []) do
    base_opts =
      Keyword.merge(
        [read_length: @default_read_length, read_timeout: @default_read_timeout],
        base_opts
      )

    case get_content_length(conn) do
      nil ->
        base_opts

      content_length ->
        timeout_opts = Keyword.take(base_opts, [:min_timeout, :min_throughput])
        dynamic_timeout = calculate_timeout(content_length, timeout_opts)

        base_opts
        |> Keyword.delete(:min_timeout)
        |> Keyword.delete(:min_throughput)
        |> Keyword.put(:read_timeout, dynamic_timeout)
    end
  end

  @doc """
  Gets the Content-Length header value from a connection.

  Returns `nil` if the header is not present or cannot be parsed.
  """
  @spec get_content_length(Plug.Conn.t()) :: non_neg_integer() | nil
  def get_content_length(conn) do
    case Plug.Conn.get_req_header(conn, "content-length") do
      [value] ->
        case Integer.parse(value) do
          {length, ""} when length >= 0 -> length
          _ -> nil
        end

      _ ->
        nil
    end
  end
end
